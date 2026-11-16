import hashlib
import json
import io
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

import sync_android_about as sync


class AndroidAboutSyncTests(unittest.TestCase):
    def test_expired_cli_token_retries_without_stale_authorization_header(self):
        failed = subprocess.CompletedProcess([], 1, b"", b"HTTP 401: Bad credentials")
        with patch.object(sync.subprocess, "run", return_value=failed), \
             patch.object(sync, "urlopen", return_value=io.BytesIO(b'{"default_branch":"master"}')) as opened:
            self.assertEqual(sync.api("")["default_branch"], "master")
        request = opened.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.github.com/repos/osfans/MCPDict")
        self.assertFalse(request.has_header("Authorization"))

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.html = root / "AndroidAbout.html"
        self.source = root / "AndroidAboutSource.json"
        self.html.write_bytes(b"<article>Existing description</article>")
        self.source.write_text(json.dumps({
            "readme_blob_sha": "old", "rendered_sha256": hashlib.sha256(self.html.read_bytes()).hexdigest()
        }))
        self.before = (self.html.read_bytes(), self.source.read_bytes())
        self.enterContext(patch.object(sync, "HTML", self.html))
        self.enterContext(patch.object(sync, "SOURCE", self.source))

    def upstream(self, blob, rendered=b"<article>Complete new description with an appendix</article>"):
        def api(path, *, rendered=False):
            if path == "":
                return {"default_branch": "master"}
            if path.startswith("commits/"):
                return {"sha": "a" * 40}
            if rendered:
                return result
            return {"sha": blob, "path": "README.md"}
        result = rendered
        return patch.object(sync, "api", side_effect=api)

    def test_same_readme_does_not_rewrite_for_unrelated_upstream_commits(self):
        with self.upstream("old") as api:
            self.assertFalse(sync.sync())
            self.assertFalse(any(call.kwargs.get("rendered") for call in api.call_args_list))
        self.assertEqual(self.before, (self.html.read_bytes(), self.source.read_bytes()))

    def test_update_saves_full_rendering_and_matching_source(self):
        content = b'<article>New description<table><tr><td>Appendix</td></tr></table></article>'
        with self.upstream("new", content):
            self.assertTrue(sync.sync())
        self.assertEqual(self.html.read_bytes(), content)
        source = json.loads(self.source.read_text())
        self.assertEqual(source["readme_blob_sha"], "new")
        self.assertEqual(source["rendered_sha256"], hashlib.sha256(content).hexdigest())
        self.assertIn("a" * 40, source["source_url"])

    def test_release_check_rejects_stale_content_without_writing(self):
        with self.upstream("new"), self.assertRaises(RuntimeError):
            sync.sync(check=True)
        self.assertEqual(self.before, (self.html.read_bytes(), self.source.read_bytes()))

    def test_release_check_rejects_modified_local_html(self):
        self.html.write_bytes(b"Truncated")
        with self.upstream("old"), self.assertRaises(RuntimeError):
            sync.sync(check=True)

    def test_fetch_failure_retains_existing_description(self):
        with patch.object(sync, "api", side_effect=RuntimeError("HTTP 503")), self.assertRaises(RuntimeError):
            sync.sync()
        self.assertEqual(self.before, (self.html.read_bytes(), self.source.read_bytes()))

    def test_unexpected_rendering_retains_existing_description(self):
        with self.upstream("new", b"<html>Error</html>"), self.assertRaises(RuntimeError):
            sync.sync()
        self.assertEqual(self.before, (self.html.read_bytes(), self.source.read_bytes()))


if __name__ == "__main__":
    unittest.main()
