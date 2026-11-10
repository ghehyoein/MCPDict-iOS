#!/bin/bash
# Run on a Mac with Xcode, XcodeGen, Python 3 and a configured Apple signing identity.
set -euo pipefail
: "${DEVELOPMENT_TEAM:?Set the Apple Developer Team ID}"
: "${BUILD_NUMBER:?Set an unused App Store Connect build number}"
: "${STABLE_IPA:?Set the path to the original 0.9.10 build 72 IPA}"
: "${ARCHIVE_PATH:?Set a new absolute .xcarchive output path}"
cd "$(dirname "$0")/.."
test ! -e "$ARCHIVE_PATH"
test "$(git rev-parse iphone-dev-72-59019d9^{commit})" = 964331d32e10718e208531c89cd75395124251f5
git merge-base --is-ancestor 964331d32e10718e208531c89cd75395124251f5 HEAD
# Reuse the exact published data, including derived indexes, without repackaging the executable.
python3 - "$STABLE_IPA" <<'PY'
import hashlib, pathlib, shutil, sys, zipfile
ipa = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
with ipa.open("rb") as source:
    for block in iter(lambda: source.read(1048576), b""):
        digest.update(block)
if digest.hexdigest() != "b6f68ebe10f72683497cdc9e7155f4bd9b0b50e98aa15e22a914521cc101e561":
    raise SystemExit("Expected original build 72 IPA")
root = pathlib.Path("App/BundledTables")
if root.exists() and any(root.iterdir()):
    raise SystemExit("Use a clean checkout with empty App/BundledTables")
prefix = "Payload/MCPDictIOS.app/BundledTables/"
with zipfile.ZipFile(ipa) as archive:
    for entry in archive.infolist():
        if entry.is_dir() or not entry.filename.startswith(prefix):
            continue
        target = root / entry.filename[len(prefix):]
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as src, target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
for required in ("catalog.json", "bundled.db", "references.db"):
    if not (root / required).is_file():
        raise SystemExit(f"Missing {required}")
PY
python3 tools/prepare_assets.py
xcodegen generate
xcodebuild -project MCPDictIOS.xcodeproj -scheme MCPDictIOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
app="$ARCHIVE_PATH/Products/Applications/MCPDictIOS.app"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")" = 0.9.10
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" = io.github.ghehyoein.MCPDictIOS
plutil -lint "$app/PrivacyInfo.xcprivacy"
codesign --verify --strict "$app"
