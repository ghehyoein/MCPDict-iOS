"""Generate a simple opaque book app icon using only the Python standard library."""
import json
from pathlib import Path
import struct
import zlib


def main():
    size = 1024
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            color = (18, 87 + y * 25 // size, 101 + y * 20 // size)
            # Two pages and a central binding, all inside the platform icon mask.
            if 210 <= x <= 488 and 230 <= y <= 764 or 536 <= x <= 814 and 230 <= y <= 764:
                color = (246, 241, 224)
            if 242 <= x <= 456 or 568 <= x <= 782:
                if any(top <= y < top + 22 for top in (330, 420, 510, 600)):
                    color = (64, 133, 137)
            raw.extend(color)
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    root = Path(__file__).resolve().parents[1] / 'App/Assets.xcassets'
    icon = root / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    (root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
    (icon / 'AppIcon.png').write_bytes(png)
    (icon / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))


if __name__ == '__main__':
    main()
