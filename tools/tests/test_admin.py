import http.client
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from admin_server import AdminError, AdminServer, ContentStore
from prepare_media import probe, sha256_file, verify_bundle


class AdminTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.media = tempfile.TemporaryDirectory()
        cls.source = Path(cls.media.name) / "sample.mp4"
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=90x160:rate=12",
            "-f", "lavfi", "-i", "sine=frequency=220:sample_rate=44100",
            "-t", "0.5", "-c:v", "libx264", "-threads", "1",
            "-pix_fmt", "yuv420p", "-c:a", "aac", str(cls.source),
        ], check=True)
        cls.metadata = probe(cls.source)

    @classmethod
    def tearDownClass(cls):
        cls.media.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "assets/videos").mkdir(parents=True)
        (self.root / "assets/posters").mkdir()
        shutil.copyfile(self.source, self.root / "assets/videos/seed.mp4")
        (self.root / "assets/posters/seed.jpg").write_bytes(b"\xff\xd8\xff\xd9")
        self.entry = {
            "id": "seed", "title": "Seed video", "assetPath": "assets/videos/seed.mp4",
            "posterAssetPath": "assets/posters/seed.jpg",
            **{key: self.metadata[key] for key in ("width", "height", "aspectRatio", "durationSeconds", "hasAudio", "orientation")},
        }
        self.write("assets/library.json", {"schemaVersion": 1, "videos": [self.entry]})
        self.write("assets/prompts.json", {"schemaVersion": 1, "promptEvery": 5, "prompts": [{"id": "p1", "line": "Look at a leaf."}, {"id": "p2", "line": "Rest your hands."}]})
        self.store = ContentStore(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def test_remove_really_excludes_video_from_bundle_and_restore_preserves_bytes(self):
        before = sha256_file(self.root / self.entry["assetPath"])
        self.assertEqual(self.store.remove("video", ["seed"]), 1)
        self.assertFalse((self.root / self.entry["assetPath"]).exists())
        self.assertFalse((self.root / self.entry["posterAssetPath"]).exists())
        self.assertEqual(self.store.library()["videos"], [])
        self.assertEqual(verify_bundle(self.root / "assets", 1), 0)
        removed = self.store.trash()["items"][0]
        self.assertEqual(self.store.restore([removed["id"]]), 1)
        self.assertEqual(sha256_file(self.root / self.entry["assetPath"]), before)
        self.assertEqual(self.store.trash()["items"], [])
        self.assertEqual(verify_bundle(self.root / "assets", 1), 0)

    def test_unknown_bulk_selection_does_not_partially_remove_files(self):
        with self.assertRaises(AdminError):
            self.store.remove("video", ["seed", "missing"])
        self.assertTrue((self.root / self.entry["assetPath"]).exists())
        self.assertEqual(len(self.store.library()["videos"]), 1)

    def test_prompt_edits_import_remove_restore_and_spacing_persist(self):
        self.store.save_prompt({"id": "p1", "line": "Notice the breeze. 🍃"})
        self.assertEqual(self.store.import_prompts("First new line\n\nSecond new line\nFirst new line", "ideas.txt"), 2)
        self.store.settings({"promptEvery": 3})
        self.store.remove("prompt", ["p1"])
        self.assertNotIn("p1", {p["id"] for p in self.store.prompts()["prompts"]})
        self.store.restore([self.store.trash()["items"][0]["id"]])
        fresh = ContentStore(self.root).prompts()
        self.assertEqual(fresh["promptEvery"], 3)
        self.assertEqual(next(p["line"] for p in fresh["prompts"] if p["id"] == "p1"), "Notice the breeze. 🍃")

    def test_import_validation_is_atomic_and_empty_prompts_are_allowed(self):
        before = self.store.prompts()
        with self.assertRaises(AdminError):
            self.store.import_prompts('["Valid", ""]', "bad.json")
        self.assertEqual(self.store.prompts(), before)
        self.store.remove("prompt", ["p1", "p2"])
        self.assertEqual(self.store.prompts()["prompts"], [])
        self.assertEqual(verify_bundle(self.root / "assets", 1), 0)

    def test_invalid_settings_and_asset_paths_are_rejected(self):
        for value in (0, -1, True, 101, "5", 2.5):
            with self.assertRaises(AdminError):
                self.store.settings({"promptEvery": value})
        for path in ("../secrets.mp4", "/tmp/secrets.mp4", "assets/videos/../../.git/config"):
            with self.assertRaises(AdminError):
                self.store.asset(path, "videos")

    def test_upload_prepares_offline_assets_and_rejects_identical_upload(self):
        staging = self.root / ".local-admin/test-upload"
        staging.mkdir(parents=True)
        source = staging / "source.mp4"
        shutil.copyfile(self.source, source)
        entry = self.store.upload_video(source, "A new leaf.mp4")
        self.assertTrue((self.root / entry["assetPath"]).is_file())
        self.assertTrue((self.root / entry["posterAssetPath"]).is_file())
        self.assertTrue((self.root / ".local-admin/originals" / entry["id"] / "A new leaf.mp4").is_file())
        self.assertTrue(entry["hasAudio"])
        self.assertEqual(entry["orientation"], "portrait")
        self.assertEqual(verify_bundle(self.root / "assets", 1), 0)
        source = staging / "duplicate.mp4"
        shutil.copyfile(self.source, source)
        with self.assertRaisesRegex(AdminError, "already"):
            self.store.upload_video(source, "Duplicate.mp4")

    def test_http_requires_local_origin_and_serves_ranges_without_exposing_git(self):
        (self.root / ".git").mkdir()
        (self.root / ".git/config").write_text("PRIVATE CONFIG")
        server = AdminServer(("127.0.0.1", 0), self.root)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def request(method, path, body=None, headers=None):
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
            connection.request(method, path, body, headers or {})
            response = connection.getresponse()
            result = (response.status, dict(response.getheaders()), response.read())
            connection.close()
            return result

        try:
            body = json.dumps({"line": "API prompt"})
            self.assertEqual(request("POST", "/api/prompts/save", body, {"Content-Type": "application/json"})[0], 403)
            self.assertEqual(request("POST", "/api/prompts/save", body, {"Content-Type": "application/json", "X-Calm-Admin": "1", "Origin": "https://example.com"})[0], 403)
            self.assertEqual(request("GET", "/api/state", headers={"Host": "example.com"})[0], 403)
            self.assertEqual(request("GET", "/assets/videos/%2e%2e/%2e%2e/.git/config")[0], 404)
            self.assertEqual(request("GET", "/.git/config")[0], 404)
            status, headers, content = request("GET", "/assets/videos/seed.mp4", headers={"Range": "bytes=0-31"})
            self.assertEqual(status, 206)
            self.assertEqual(len(content), 32)
            self.assertTrue(headers["Content-Range"].startswith("bytes 0-31/"))
            self.assertEqual(request("POST", "/api/prompts/save", body, {"Content-Type": "application/json", "X-Calm-Admin": "1"})[0], 200)
            self.assertTrue(any(p["line"] == "API prompt" for p in self.store.prompts()["prompts"]))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
