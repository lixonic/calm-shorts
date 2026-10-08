#!/usr/bin/env python3
"""Build Calm Reels' bundled offline media without modifying any source videos.

Requires ffmpeg with libx264 and ffprobe. From any directory run:
    python3 calm_reels/tools/prepare_media.py

An interrupted run can be repeated. Each completed output has a source hash,
output hash, encoder settings, and verified stream metadata in the manifest.
Verified fast-preset outputs are retained when resuming with veryfast; the
manifest and summary report the actual preset used for every output.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


APP_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_ROOT = APP_ROOT.parent
DEFAULT_CATALOG = DEFAULT_SOURCE_ROOT / "catalog" / "video_catalog.json"
ENCODING = {
    "version": 1,
    "videoCodec": "libx264",
    "pixelFormat": "yuv420p",
    "crf": 25,
    "preset": "veryfast",
    "maxRateKbps": 1800,
    "bufferSizeKbps": 3600,
    "portraitMaxWidth": 720,
    "portraitMaxHeight": 1280,
    "landscapeMaxWidth": 1280,
    "landscapeMaxHeight": 720,
    "audioCodec": "aac",
    "audioBitrateKbps": 96,
    "maxAudioChannels": 2,
    "encoderThreads": 2,
    "posterMaxWidth": 240,
    "posterMaxHeight": 426,
}


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".partial")
    partial.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    os.replace(partial, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def run_command(command: list[str]) -> subprocess.CompletedProcess:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[-6000:] or f"Command failed: {command[0]}")
    return result


def probe(path: Path) -> dict:
    data = json.loads(run_command([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)
    ]).stdout)
    videos = [s for s in data.get("streams", []) if s.get("codec_type") == "video"
              and not s.get("disposition", {}).get("attached_pic")]
    if not videos:
        raise RuntimeError(f"No video stream in {path.name}")
    audio = [s for s in data.get("streams", []) if s.get("codec_type") == "audio"]
    stream = videos[0]
    width, height = int(stream["width"]), int(stream["height"])
    sar_text = stream.get("sample_aspect_ratio", "1:1")
    try:
        sar = Fraction(sar_text.replace(":", "/"))
    except (ValueError, ZeroDivisionError):
        sar = Fraction(1)
    if not sar:
        sar = Fraction(1)
    aspect = Fraction(width, height) * sar
    return {
        "width": width,
        "height": height,
        "aspectRatio": float(aspect),
        "durationSeconds": float(data.get("format", {}).get("duration") or stream["duration"]),
        "hasAudio": bool(audio),
        "orientation": "portrait" if aspect <= 1 else "landscape",
        "codec": stream.get("codec_name"),
        "pixelFormat": stream.get("pix_fmt"),
        "audioCodec": audio[0].get("codec_name") if audio else None,
        "audioChannels": audio[0].get("channels") if audio else 0,
    }


def clean_title(item: dict) -> str:
    title = str(item.get("draft_title") or Path(item["relative_path"]).stem)
    title = re.sub(r"(?:[_\s-]+)?\d{8,14}(?:[_\s-]+[a-z0-9]+)?$", "", title)
    title = re.sub(r"[_\s]+", " ", title).strip(" ._-")
    title = re.sub(
        r"(?:\s+(?:a|an|the|at|in|on|of|from|with|and|into|over|under|through|for|is|as|to|beside))+$",
        "", title, flags=re.IGNORECASE,
    ).strip()
    return title or "Calm moment"


def prepare_one(item: dict, source_root: Path, output_root: Path,
                previous: dict | None, force: bool, make_poster: bool) -> tuple[dict, dict, bool]:
    started = time.monotonic()
    source = (source_root / item["relative_path"]).resolve()
    if not source.is_relative_to(source_root.resolve()) or not source.is_file():
        raise RuntimeError(f"Source missing or outside media root: {item['relative_path']}")
    video_id = str(item["id"])
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", video_id):
        raise RuntimeError(f"Invalid catalog id: {video_id}")
    output = output_root / "videos" / f"{video_id}.mp4"
    poster = output_root / "posters" / f"{video_id}.jpg"
    stat = source.stat()
    fingerprint = {
        "relativePath": item["relative_path"],
        "byteSize": stat.st_size,
        "mtimeNs": stat.st_mtime_ns,
        "sha256": sha256_file(source),
    }
    reused = False
    metadata = None
    actual_encoding = ENCODING
    compatible_encoding = previous and all(
        previous.get("encoding", {}).get(key) == value
        for key, value in ENCODING.items() if key != "preset"
    ) and previous.get("encoding", {}).get("preset") in ("fast", "veryfast")
    if not force and previous and previous.get("source") == fingerprint \
            and compatible_encoding and output.is_file():
        if output.stat().st_size == previous.get("outputByteSize") \
                and sha256_file(output) == previous.get("outputSha256"):
            metadata = probe(output)
            reused = True
            actual_encoding = previous["encoding"]
    if metadata is None:
        orientation = item.get("video", {}).get("orientation", "exact_9_16")
        max_width, max_height = (
            (ENCODING["landscapeMaxWidth"], ENCODING["landscapeMaxHeight"])
            if orientation == "landscape" else
            (ENCODING["portraitMaxWidth"], ENCODING["portraitMaxHeight"])
        )
        scale = (
            f"scale=w='min(iw,{max_width})':h='min(ih,{max_height})':"
            "force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1"
        )
        partial = output.with_name(output.stem + ".partial.mp4")
        command = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-threads", str(ENCODING["encoderThreads"]),
            "-i", str(source), "-map", "0:v:0", "-map", "0:a:0?",
            "-map_metadata", "-1", "-vf", scale,
            "-c:v", ENCODING["videoCodec"], "-preset", ENCODING["preset"],
            "-crf", str(ENCODING["crf"]), "-maxrate", f"{ENCODING['maxRateKbps']}k",
            "-bufsize", f"{ENCODING['bufferSizeKbps']}k", "-pix_fmt", ENCODING["pixelFormat"],
            "-threads", str(ENCODING["encoderThreads"]),
        ]
        source_audio = item.get("audio_streams", [])
        if item.get("has_audio"):
            channels = min(ENCODING["maxAudioChannels"], max(1, int(source_audio[0].get("channels", 2)))) \
                if source_audio else ENCODING["maxAudioChannels"]
            command += ["-c:a", ENCODING["audioCodec"], "-b:a",
                        f"{ENCODING['audioBitrateKbps']}k", "-ac", str(channels)]
        else:
            command += ["-an"]
        command += ["-movflags", "+faststart", str(partial)]
        try:
            run_command(command)
            metadata = probe(partial)
            if metadata["codec"] != "h264" or metadata["pixelFormat"] != "yuv420p":
                raise RuntimeError(f"Unexpected output codec in {video_id}")
            if metadata["hasAudio"] != bool(item.get("has_audio")):
                raise RuntimeError(f"Audio preservation failed for {video_id}")
            if abs(metadata["durationSeconds"] - float(item["duration_seconds"])) > 0.6:
                raise RuntimeError(f"Duration mismatch for {video_id}")
            if metadata["width"] > max_width or metadata["height"] > max_height:
                raise RuntimeError(f"Output dimensions exceed bounds for {video_id}")
            if source.stat().st_size != fingerprint["byteSize"] \
                    or source.stat().st_mtime_ns != fingerprint["mtimeNs"]:
                raise RuntimeError(f"Source changed during preparation: {video_id}")
            os.replace(partial, output)
        finally:
            if partial.exists():
                partial.unlink()
    if make_poster and (not reused or not poster.is_file()
                        or previous.get("posterSha256") != sha256_file(poster)):
        poster_time = min(0.4, metadata["durationSeconds"] / 4)
        partial_poster = poster.with_name(poster.stem + ".partial.jpg")
        poster_filter = (
            f"scale=w='min(iw,{ENCODING['posterMaxWidth']})':"
            f"h='min(ih,{ENCODING['posterMaxHeight']})':"
            "force_original_aspect_ratio=decrease:force_divisible_by=2"
        )
        try:
            run_command([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "1",
                "-ss", str(poster_time), "-i", str(output), "-frames:v", "1",
                "-vf", poster_filter, "-q:v", "5", "-threads", "1", str(partial_poster)
            ])
            if not partial_poster.is_file() or partial_poster.stat().st_size == 0:
                raise RuntimeError(f"No poster generated for {video_id}")
            os.replace(partial_poster, poster)
        finally:
            if partial_poster.exists():
                partial_poster.unlink()
    entry = {
        "id": video_id,
        "assetPath": f"assets/videos/{video_id}.mp4",
        "title": clean_title(item),
        "aspectRatio": metadata["aspectRatio"],
        "width": metadata["width"],
        "height": metadata["height"],
        "durationSeconds": metadata["durationSeconds"],
        "hasAudio": metadata["hasAudio"],
        "orientation": metadata["orientation"],
    }
    if make_poster:
        entry["posterAssetPath"] = f"assets/posters/{video_id}.jpg"
    manifest = {
        "source": fingerprint,
        "encoding": actual_encoding,
        "outputByteSize": output.stat().st_size,
        "outputSha256": sha256_file(output),
        "posterByteSize": poster.stat().st_size if make_poster else 0,
        "posterSha256": sha256_file(poster) if make_poster else None,
        "verifiedMetadata": metadata,
        "entry": entry,
        "preparationSeconds": round(time.monotonic() - started, 3),
    }
    return entry, manifest, reused


def verify_bundle(output_root: Path, jobs: int) -> int:
    """Validate published assets independently of the source collection."""
    library = json.loads((output_root / "library.json").read_text())
    videos = library.get("videos", [])
    if library.get("schemaVersion") != 1 or not videos:
        raise RuntimeError("Invalid or empty bundled library")
    if len({item["id"] for item in videos}) != len(videos):
        raise RuntimeError("Bundled library contains repeated ids")
    failures = []

    def bundled_path(asset_path: str) -> Path:
        relative = Path(asset_path)
        if relative.is_absolute() or not relative.parts or relative.parts[0] != "assets":
            raise RuntimeError("Expected an assets/... path")
        path = output_root.joinpath(*relative.parts[1:]).resolve()
        if not path.is_relative_to(output_root.resolve()):
            raise RuntimeError("Asset is outside the bundled directory")
        return path

    def check(item: dict) -> None:
        path = bundled_path(item["assetPath"])
        if not path.is_file():
            raise RuntimeError("Video missing or outside asset directory")
        data = probe(path)
        if data["codec"] != "h264" or data["pixelFormat"] != "yuv420p":
            raise RuntimeError("Expected H.264 yuv420p video")
        for field in ("width", "height", "hasAudio", "orientation"):
            if data[field] != item[field]:
                raise RuntimeError(f"Manifest mismatch: {field}")
        if abs(data["durationSeconds"] - item["durationSeconds"]) > 0.1:
            raise RuntimeError("Manifest duration mismatch")
        if abs(data["aspectRatio"] - item["aspectRatio"]) > 0.001:
            raise RuntimeError("Manifest aspect ratio mismatch")
        if data["hasAudio"] and data["audioCodec"] != "aac":
            raise RuntimeError("Expected AAC audio")
        if path.stat().st_size >= 100_000_000:
            raise RuntimeError("Video exceeds the 100 MB ordinary Git file limit")
        if item.get("posterAssetPath"):
            poster = bundled_path(item["posterAssetPath"])
            if not poster.is_file():
                raise RuntimeError("Poster missing or outside asset directory")
            if poster.stat().st_size < 4 or poster.read_bytes()[:2] != b"\xff\xd8":
                raise RuntimeError("Poster is not a nonempty JPEG")

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        pending = {pool.submit(check, item): item for item in videos}
        for future in as_completed(pending):
            item = pending[future]
            try:
                future.result()
            except Exception as error:
                failures.append(f"{item['id']}: {error}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Verified {len(videos)} bundled videos and their posters.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--output-root", type=Path, default=APP_ROOT / "assets")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--preset", choices=("fast", "veryfast"), default=ENCODING["preset"])
    parser.add_argument("--force", action="store_true", help="Re-encode verified cached outputs")
    parser.add_argument("--ids", help="Only prepare these comma-separated catalog ids")
    parser.add_argument("--no-posters", action="store_true")
    parser.add_argument("--verify-bundle", action="store_true",
                        help="Check the published bundle without catalog or source originals")
    args = parser.parse_args()
    ENCODING["preset"] = args.preset
    for executable in (("ffprobe",) if args.verify_bundle else ("ffmpeg", "ffprobe")):
        if not shutil.which(executable):
            parser.error(f"Required program not found: {executable}")
    if args.jobs < 1 or args.jobs > 4:
        parser.error("Use 1–4 workers; two are recommended")
    if args.verify_bundle:
        return verify_bundle(args.output_root, args.jobs)
    catalog = json.loads(args.catalog.read_text())
    videos = [item for item in catalog["videos"] if not item.get("is_duplicate_copy", False)]
    ids = set(args.ids.split(",")) if args.ids else None
    if ids:
        videos = [item for item in videos if item["id"] in ids]
        missing = ids - {item["id"] for item in videos}
        if missing:
            parser.error(f"Unknown or duplicate-only ids: {', '.join(sorted(missing))}")
    if not videos:
        parser.error("No canonical source videos selected")
    if len({item["id"] for item in videos}) != len(videos):
        parser.error("Catalog ids must be unique")
    args.output_root.mkdir(parents=True, exist_ok=True)
    (args.output_root / "videos").mkdir(exist_ok=True)
    (args.output_root / "posters").mkdir(exist_ok=True)
    # Keep a custom destination's cache and summary with that destination; the
    # normal app cache stays outside the Flutter asset bundle.
    state_root = APP_ROOT / "tools" if args.output_root.resolve() == (APP_ROOT / "assets").resolve() \
        else args.output_root
    manifest_path = state_root / "media_preparation_manifest.json"
    summary_path = state_root / "media_preparation_summary.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        manifest = {"schemaVersion": 1, "videos": {}}
    cache = manifest.get("videos", {})
    entries = {}
    failures = []
    reused_count = 0
    started = time.monotonic()

    def summary(status: str) -> dict:
        selected_records = [cache[item["id"]] for item in videos if item["id"] in entries]
        return {
            "schemaVersion": 1,
            "updatedAt": datetime.now(timezone.utc).isoformat(),
            "status": status,
            "sourceVideoCount": len(videos),
            "completedVideoCount": len(entries),
            "reusedVideoCount": reused_count,
            "portraitCount": sum(e["orientation"] == "portrait" for e in entries.values()),
            "landscapeCount": sum(e["orientation"] == "landscape" for e in entries.values()),
            "sourceBytes": sum(item["byte_size"] for item in videos),
            "preparedVideoBytes": sum(r["outputByteSize"] for r in selected_records),
            "posterBytes": sum(r["posterByteSize"] for r in selected_records),
            "durationSeconds": sum(e["durationSeconds"] for e in entries.values()),
            "elapsedSeconds": round(time.monotonic() - started, 3),
            "encoding": ENCODING,
            "presetCounts": {
                preset: sum(r["encoding"]["preset"] == preset for r in selected_records)
                for preset in ("fast", "veryfast")
                if any(r["encoding"]["preset"] == preset for r in selected_records)
            },
            "verification": "Every prepared or reused MP4 is checked with ffprobe; hashes and full durations are verified.",
            "failures": failures,
        }

    print(f"Preparing {len(videos)} unique videos with {args.jobs} workers", flush=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = {
            pool.submit(prepare_one, item, args.source_root, args.output_root,
                        cache.get(item["id"]), args.force, not args.no_posters): item
            for item in videos
        }
        for future in as_completed(pending):
            item = pending[future]
            try:
                entry, record, reused = future.result()
                entries[entry["id"]] = entry
                cache[entry["id"]] = record
                reused_count += int(reused)
                print(f"[{len(entries)}/{len(videos)}] {'Reused' if reused else 'Prepared'} "
                      f"{item['relative_path']} ({record['outputByteSize'] / 1_000_000:.2f} MB, "
                      f"{record['preparationSeconds']:.1f}s)", flush=True)
                atomic_json(manifest_path, {"schemaVersion": 1, "videos": cache})
                atomic_json(summary_path, summary("running"))
            except Exception as error:
                failures.append({"id": item["id"], "source": item["relative_path"], "error": str(error)})
                print(f"FAILED {item['relative_path']}: {error}", file=sys.stderr, flush=True)
    if failures:
        atomic_json(summary_path, summary("failed"))
        print(f"{len(failures)} failed videos. No incomplete library published.", file=sys.stderr)
        return 1
    ordered_entries = [entries[item["id"]] for item in videos]
    atomic_json(args.output_root / "library.json", {"schemaVersion": 1, "videos": ordered_entries})
    final_summary = summary("complete")
    atomic_json(summary_path, final_summary)
    print(json.dumps(final_summary, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
