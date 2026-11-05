"""Reuse the Android upstream Play Store icon; resize with macOS sips for Xcode.
Source: osfans/MCPDict app/src/main/ic_launcher-playstore.png
Commit: d88e3bcaff6f17399a33bc3010794ed1c2dd707e; see UPSTREAM-LICENSE.txt.
"""
import base64
import json
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1] / 'App/Assets.xcassets'
    icon = root / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    image = icon / 'AppIcon.png'
    image.write_bytes(base64.b64decode(Path(__file__).with_name('android_icon.png.b64').read_text()))
    if sys.platform == 'darwin':
        subprocess.run(['sips', '-z', '1024', '1024', str(image)], check=True, capture_output=True)
    else:
        # Windows preview uses the original source asset. CI emits the 1024px icon.
        print('Original Android icon saved; macOS build resizes it to 1024px.')
    (root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
    (icon / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))


if __name__ == '__main__':
    main()
