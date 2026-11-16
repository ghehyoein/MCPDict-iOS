#!/usr/bin/env python3
"""Refresh the bundled Android README before a release; --check never writes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "App/AndroidAbout.html"
SOURCE = ROOT / "App/AndroidAboutSource.json"
REPOSITORY = "osfans/MCPDict"


def api(path, *, rendered=False):
    command = ["gh", "api", f"repos/{REPOSITORY}/{path}".rstrip("/")]
    if rendered:
        command += ["-H", "Accept: application/vnd.github.html+json"]
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        # Do not print authentication configuration or response bodies.
        status = re.search(rb"HTTP (\d{3})", result.stderr)
        if status and status[1] == b"401":
            # An inherited CLI token may expire while the managed proxy's
            # identity remains valid. Retry this public README endpoint without
            # the stale header, preserving the environment's proxy and CA trust.
            request = Request("https://api.github.com/" + command[2], headers={
                "Accept": "application/vnd.github.html+json" if rendered else "application/vnd.github+json",
                "User-Agent": "MCPDict-iOS-about-sync",
            })
            try:
                with urlopen(request, timeout=30) as response:
                    body = response.read()
                return body if rendered else json.loads(body)
            except HTTPError as error:
                raise RuntimeError(f"Cannot check Android README: HTTP {error.code}") from None
            except URLError:
                raise RuntimeError("Cannot check Android README: network connection failed") from None
        detail = f"HTTP {status[1].decode()}" if status else "network or GitHub authentication error"
        raise RuntimeError(f"Cannot check Android README: {detail}")
    return result.stdout if rendered else json.loads(result.stdout)


def sync(*, check=False):
    branch = api("")["default_branch"]
    commit = api("commits/" + quote(branch, safe=""))["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RuntimeError("Invalid upstream commit identifier")
    readme = api("readme?ref=" + commit)
    source = json.loads(SOURCE.read_text()) if SOURCE.exists() else {}
    current = HTML.read_bytes() if HTML.exists() else b""
    same_content = source.get("readme_blob_sha") == readme["sha"]
    intact = source.get("rendered_sha256") == hashlib.sha256(current).hexdigest()
    if same_content and intact:
        print("Android README is current; bundled description unchanged.")
        return False
    if check:
        raise RuntimeError("Android README needs syncing. Run python3 tools/sync_android_about.py, commit the update, and validate that commit before publishing.")
    rendered = api("readme?ref=" + commit, rendered=True)
    if b'<article' not in rendered or b'<script' in rendered.lower() or b'<iframe' in rendered.lower():
        raise RuntimeError("Unexpected upstream README rendering; existing description retained")
    metadata = {
        "repository": REPOSITORY,
        "source_commit": commit,
        "readme_blob_sha": readme["sha"],
        "source_url": f"https://github.com/{REPOSITORY}/blob/{commit}/{quote(readme['path'])}",
        "rendered_sha256": hashlib.sha256(rendered).hexdigest(),
    }
    HTML.write_bytes(rendered)
    SOURCE.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    print(f"Updated the complete Android README from {commit[:7]}.")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        sync(check=args.check)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
