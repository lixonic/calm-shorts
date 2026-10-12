#!/usr/bin/env python3
"""Local-only content manager. Run: python3 tools/admin_server.py"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import re
import shutil
import tempfile
import threading
from urllib.parse import parse_qs, unquote, urlsplit
import uuid

from prepare_media import atomic_json, prepare_one, probe, sha256_file


APP_ROOT = Path(__file__).resolve().parents[1]
MAX_UPLOAD = 2 * 1024**3
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi"}


class AdminError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def prompt_text(value: object) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 2000:
        raise AdminError("Enter a prompt between 1 and 2,000 characters.")
    return value.strip()


class ContentStore:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.assets = self.root / "assets"
        self.local = self.root / ".local-admin"
        self.lock = threading.RLock()

    def read(self, path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    def library(self) -> dict:
        return self.read(self.assets / "library.json")

    def prompts(self) -> dict:
        return self.read(self.assets / "prompts.json")

    def trash(self) -> dict:
        path = self.local / "trash/index.json"
        return self.read(path) if path.exists() else {"items": []}

    def asset(self, relative: str, folder: str) -> Path:
        if not isinstance(relative, str):
            raise AdminError("Invalid asset path.")
        path = (self.root / relative).resolve()
        expected = (self.assets / folder).resolve()
        if Path(relative).is_absolute() or not path.is_relative_to(expected):
            raise AdminError("Asset path must remain inside its content folder.")
        return path

    def state(self) -> dict:
        with self.lock:
            library, prompts, trash = self.library(), self.prompts(), self.trash()
            videos = []
            for entry in library["videos"]:
                row = dict(entry)
                path = self.asset(entry["assetPath"], "videos")
                row["byteSize"] = path.stat().st_size if path.is_file() else 0
                row["filename"] = path.name
                videos.append(row)
            return {
                "videos": videos,
                "prompts": prompts["prompts"],
                "promptEvery": prompts["promptEvery"],
                "trash": trash["items"],
                "root": str(self.root),
                "videoBytes": sum(v["byteSize"] for v in videos),
                "viewerOrientation": "portrait",
            }

    def upload_video(self, source: Path, name: str) -> dict:
        if Path(name).suffix.lower() not in VIDEO_EXTENSIONS:
            raise AdminError("Choose an MP4, MOV, M4V, MKV, WebM, or AVI video.")
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            raise AdminError("Install FFmpeg to prepare uploaded videos.")
        try:
            metadata = probe(source)
        except Exception as error:
            raise AdminError("This file could not be read as a video.") from error
        if metadata["durationSeconds"] <= 0:
            raise AdminError("The video must have a positive duration.")
        source_hash = sha256_file(source)
        with self.lock:
            existing = self.library()["videos"]
            active_ids = {v["id"] for v in existing}
            original_manifest = self.root / "tools/media_preparation_manifest.json"
            known_hashes = {v.get("sourceSha256") for v in existing}
            if original_manifest.is_file():
                known_hashes.update(
                    record.get("source", {}).get("sha256")
                    for key, record in self.read(original_manifest).get("videos", {}).items()
                    if key in active_ids
                )
            if source_hash in known_hashes:
                raise AdminError("This video is already in the library.", 409)
        video_id = uuid.uuid4().hex[:16]
        output = source.parent / "prepared"
        (output / "videos").mkdir(parents=True)
        (output / "posters").mkdir()
        item = {
            "id": video_id, "relative_path": source.name,
            "draft_title": Path(name).stem.replace("_", " "),
            "has_audio": metadata["hasAudio"],
            "duration_seconds": metadata["durationSeconds"],
        }
        try:
            entry, record, _ = prepare_one(item, source.parent, output, None, False, True)
        except Exception as error:
            raise AdminError("Video preparation failed. The existing library was not changed.") from error
        prepared = output / "videos" / f"{video_id}.mp4"
        poster = output / "posters" / f"{video_id}.jpg"
        if prepared.stat().st_size >= 100_000_000:
            raise AdminError("The prepared video exceeds 100 MB. Upload a shorter clip.")
        entry.update(sourceSha256=source_hash, originalName=name, addedAt=now())
        with self.lock:
            library = self.library()
            if any(v.get("sourceSha256") == source_hash for v in library["videos"]):
                raise AdminError("This video was already uploaded.", 409)
            target = self.asset(entry["assetPath"], "videos")
            target_poster = self.asset(entry["posterAssetPath"], "posters")
            target.parent.mkdir(parents=True, exist_ok=True)
            target_poster.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(prepared), target)
            shutil.move(str(poster), target_poster)
            try:
                library["videos"].append(entry)
                atomic_json(self.assets / "library.json", library)
            except Exception:
                target.unlink(missing_ok=True)
                target_poster.unlink(missing_ok=True)
                raise
            original = self.local / "originals" / video_id
            original.mkdir(parents=True)
            shutil.move(str(source), original / Path(name).name)
            atomic_json(original / "preparation.json", record)
        return entry

    def save_prompt(self, values: dict) -> dict:
        line = prompt_text(values.get("line"))
        with self.lock:
            data = self.prompts()
            prompt_id = values.get("id")
            if prompt_id:
                entry = next((p for p in data["prompts"] if p["id"] == prompt_id), None)
                if entry is None:
                    raise AdminError("Prompt no longer exists.", 404)
                entry["line"] = line
            else:
                entry = {"id": "p-" + uuid.uuid4().hex[:12], "line": line}
                data["prompts"].append(entry)
            atomic_json(self.assets / "prompts.json", data)
            return entry

    def import_prompts(self, text: str, name: str) -> int:
        if Path(name).suffix.lower() == ".json":
            try:
                data = json.loads(text)
                rows = data.get("prompts") if isinstance(data, dict) else data
                if not isinstance(rows, list):
                    raise ValueError()
                lines = [prompt_text(p.get("line") if isinstance(p, dict) else p) for p in rows]
            except (ValueError, TypeError) as error:
                raise AdminError("Use a JSON list of strings or prompts with a line field.") from error
        elif Path(name).suffix.lower() == ".txt":
            lines = [prompt_text(line) for line in text.splitlines() if line.strip()]
        else:
            raise AdminError("Upload a TXT file (one prompt per line) or a JSON prompt list.")
        if not lines or len(lines) > 5000:
            raise AdminError("Upload between 1 and 5,000 prompts.")
        with self.lock:
            data = self.prompts()
            existing = {p["line"] for p in data["prompts"]}
            added = 0
            for line in lines:
                if line not in existing:
                    data["prompts"].append({"id": "p-" + uuid.uuid4().hex[:12], "line": line})
                    existing.add(line)
                    added += 1
            atomic_json(self.assets / "prompts.json", data)
            return added

    def rename_video(self, values: dict) -> None:
        title = prompt_text(values.get("title"))
        with self.lock:
            data = self.library()
            entry = next((v for v in data["videos"] if v["id"] == values.get("id")), None)
            if entry is None:
                raise AdminError("Video no longer exists.", 404)
            entry["title"] = title
            atomic_json(self.assets / "library.json", data)

    def remove(self, kind: str, ids: list) -> int:
        if kind not in ("video", "prompt") or not isinstance(ids, list) or not ids:
            raise AdminError("Select videos or prompts to remove.")
        if not all(isinstance(item, str) for item in ids):
            raise AdminError("Invalid selection.")
        with self.lock:
            path = self.assets / ("library.json" if kind == "video" else "prompts.json")
            data = self.read(path)
            key = "videos" if kind == "video" else "prompts"
            selected = [v for v in data[key] if v["id"] in set(ids)]
            if len(selected) != len(set(ids)):
                raise AdminError("An item no longer exists. Refresh and try again.", 409)
            trash = self.trash()
            moved = []
            try:
                for entry in selected:
                    token = uuid.uuid4().hex
                    row = {"id": token, "kind": kind, "entry": entry, "removedAt": now()}
                    if kind == "video":
                        folder = self.local / "trash" / token
                        folder.mkdir(parents=True)
                        for field, group in (("assetPath", "videos"), ("posterAssetPath", "posters")):
                            if entry.get(field):
                                source = self.asset(entry[field], group)
                                if not source.is_file():
                                    raise AdminError("A selected video or poster is missing.")
                                target = folder / source.name
                                shutil.move(str(source), target)
                                moved.append((target, source))
                    trash["items"].append(row)
                data[key] = [v for v in data[key] if v["id"] not in set(ids)]
                old_trash = self.trash()
                atomic_json(self.local / "trash/index.json", trash)
                try:
                    atomic_json(path, data)
                except Exception:
                    atomic_json(self.local / "trash/index.json", old_trash)
                    raise
            except Exception:
                for source, target in reversed(moved):
                    shutil.move(str(source), target)
                raise
            return len(selected)

    def restore(self, ids: list) -> int:
        if not isinstance(ids, list) or not ids or not all(isinstance(i, str) for i in ids):
            raise AdminError("Select items to restore.")
        with self.lock:
            trash = self.trash()
            rows = [row for row in trash["items"] if row["id"] in set(ids)]
            if len(rows) != len(set(ids)):
                raise AdminError("An item is no longer in Recently removed.", 409)
            library, prompts = self.library(), self.prompts()
            moved = []
            old_library, old_prompts, old_trash = self.library(), self.prompts(), self.trash()
            try:
                for row in rows:
                    entry = row["entry"]
                    pool = library["videos"] if row["kind"] == "video" else prompts["prompts"]
                    if any(e["id"] == entry["id"] for e in pool):
                        raise AdminError("An item with this ID already exists.", 409)
                    if row["kind"] == "video":
                        if not re.fullmatch(r"[a-f0-9]{32}", row["id"]):
                            raise AdminError("Invalid removed item.")
                        folder = self.local / "trash" / row["id"]
                        for field, group in (("assetPath", "videos"), ("posterAssetPath", "posters")):
                            if entry.get(field):
                                target = self.asset(entry[field], group)
                                source = folder / target.name
                                if target.exists() or not source.is_file():
                                    raise AdminError("Cannot restore this file without overwriting another item.", 409)
                                target.parent.mkdir(parents=True, exist_ok=True)
                                shutil.move(str(source), target)
                                moved.append((target, source))
                    pool.append(entry)
                trash["items"] = [r for r in trash["items"] if r["id"] not in set(ids)]
                atomic_json(self.assets / "library.json", library)
                atomic_json(self.assets / "prompts.json", prompts)
                atomic_json(self.local / "trash/index.json", trash)
            except Exception:
                for source, target in reversed(moved):
                    shutil.move(str(source), target)
                atomic_json(self.assets / "library.json", old_library)
                atomic_json(self.assets / "prompts.json", old_prompts)
                atomic_json(self.local / "trash/index.json", old_trash)
                raise
            return len(rows)

    def settings(self, values: dict) -> None:
        interval = values.get("promptEvery")
        if type(interval) is not int or not 1 <= interval <= 100:
            raise AdminError("Show a prompt after 1 to 100 videos.")
        with self.lock:
            data = self.prompts()
            data["promptEvery"] = interval
            atomic_json(self.assets / "prompts.json", data)


class AdminServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, root: Path):
        self.store = ContentStore(root)
        super().__init__(address, AdminHandler)


class AdminHandler(BaseHTTPRequestHandler):
    server: AdminServer
    protocol_version = "HTTP/1.1"

    def local_request(self, mutation=False) -> None:
        port = self.server.server_port
        hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        if self.headers.get("Host") not in hosts:
            raise AdminError("Use the local admin address.", 403)
        origin = self.headers.get("Origin")
        if origin and origin not in {"http://" + h for h in hosts}:
            raise AdminError("Requests must come from the local admin.", 403)
        if mutation and self.headers.get("X-Calm-Admin") != "1":
            raise AdminError("Open the local admin to make changes.", 403)

    def reply(self, status: int, data: dict) -> None:
        encoded = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(encoded)

    def length(self, limit: int) -> int:
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise AdminError("Invalid upload size.") from error
        if self.headers.get("Transfer-Encoding") or size < 1 or size > limit:
            raise AdminError("File is empty or exceeds the upload size limit.", 413)
        return size

    def do_POST(self):
        try:
            self.local_request(mutation=True)
            self.connection.settimeout(120)
            route = urlsplit(self.path)
            store = self.server.store
            if route.path == "/api/videos/upload":
                size = self.length(MAX_UPLOAD)
                name = parse_qs(route.query).get("name", [""])[0]
                name = Path(name.replace("\\", "/")).name
                if len(name) > 240 or Path(name).suffix.lower() not in VIDEO_EXTENSIONS:
                    raise AdminError("Choose a supported video file.")
                staging = store.local / "uploads"
                staging.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(dir=staging) as directory:
                    source = Path(directory) / ("source" + Path(name).suffix.lower())
                    with source.open("wb") as handle:
                        while size:
                            chunk = self.rfile.read(min(size, 1024 * 1024))
                            if not chunk:
                                raise AdminError("Upload interrupted. Please try again.")
                            handle.write(chunk)
                            size -= len(chunk)
                    entry = store.upload_video(source, name)
                self.reply(201, {"video": entry})
                return
            size = self.length(2 * 1024 * 1024)
            if self.headers.get_content_type() != "application/json":
                raise AdminError("Expected a JSON request.", 415)
            try:
                values = json.loads(self.rfile.read(size))
                if not isinstance(values, dict):
                    raise ValueError()
            except (ValueError, UnicodeError) as error:
                raise AdminError("Invalid request.") from error
            if route.path == "/api/prompts/save":
                result = {"prompt": store.save_prompt(values)}
            elif route.path == "/api/prompts/import":
                if not isinstance(values.get("text"), str) or not isinstance(values.get("name"), str):
                    raise AdminError("Choose a prompt file.")
                result = {"count": store.import_prompts(values["text"], values["name"])}
            elif route.path == "/api/videos/rename":
                store.rename_video(values)
                result = {"ok": True}
            elif route.path == "/api/remove":
                result = {"count": store.remove(values.get("kind"), values.get("ids"))}
            elif route.path == "/api/restore":
                result = {"count": store.restore(values.get("ids"))}
            elif route.path == "/api/settings":
                store.settings(values)
                result = {"ok": True}
            else:
                raise AdminError("Unknown action.", 404)
            self.reply(200, result)
        except AdminError as error:
            self.close_connection = True
            self.reply(error.status, {"error": str(error)})
        except Exception as error:
            self.close_connection = True
            print(f"Admin action failed: {error}", flush=True)
            self.reply(500, {"error": "The change could not be saved. Check the local server output."})

    def do_GET(self):
        try:
            self.local_request()
            route = unquote(urlsplit(self.path).path)
            if route == "/api/state":
                self.reply(200, self.server.store.state())
                return
            if route in ("/", "/admin"):
                route = "/admin/"
            if route.endswith("/"):
                route += "index.html"
            allowed = ("/admin/", "/preview/", "/assets/videos/", "/assets/posters/")
            folder = next((prefix for prefix in allowed if route.startswith(prefix)), None)
            if folder is None and route not in ("/assets/library.json", "/assets/prompts.json"):
                raise AdminError("File not found.", 404)
            path = (self.server.store.root / route.lstrip("/")).resolve()
            boundary = self.server.store.root / folder.lstrip("/") if folder else self.server.store.assets
            if not path.is_relative_to(boundary.resolve()) or not path.is_file() or path.name.startswith("."):
                raise AdminError("File not found.", 404)
            self.send_file(path)
        except AdminError as error:
            self.reply(error.status, {"error": str(error)})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as error:
            print(f"Admin read failed: {error}", flush=True)
            self.reply(500, {"error": "The content library could not be read."})

    def send_file(self, path: Path) -> None:
        total = path.stat().st_size
        start, end = 0, total - 1
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested)
            if not match or not any(match.groups()):
                raise AdminError("Invalid media range.", 416)
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), end) if last else end
            else:
                start = max(0, total - int(last))
            if start > end or start >= total:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{total}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        self.send_response(206 if requested else 200)
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        if path.suffix in (".html", ".js", ".css"):
            self.send_header("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'")
        if requested:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        self.end_headers()
        with path.open("rb") as handle:
            handle.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = handle.read(min(remaining, 256 * 1024))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def log_message(self, format, *args):
        if str(args[1]) not in ("200", "206"):
            super().log_message(format, *args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--root", type=Path, default=APP_ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    local = root / ".local-admin"
    local.mkdir(parents=True, exist_ok=True)
    with (local / "admin.lock").open("w") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("An admin is already running for this project.")
        server = AdminServer(("127.0.0.1", args.port), root)
        print(f"Calm Reels admin: http://127.0.0.1:{server.server_port}/admin/", flush=True)
        print(f"Saving content in: {root}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == "__main__":
    main()
