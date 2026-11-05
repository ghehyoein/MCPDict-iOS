"""Pin and verify the MapLibre assets bundled with the iOS web map."""
from pathlib import Path
import hashlib
import urllib.request

ASSETS = {
    'maplibre-gl.js': 'b5a34e6930ff937dbbb9eec8892cffb80ba473cce88ae5ca8c4654432f5f0ebc',
    'maplibre-gl.css': '792ac997dcf6ae6f643eb4e2dee4630c85e7056526bd8fb85ffe83c67d6c41b4',
    'LICENSE.txt': 'ee5fc05a0677eaf69601d2c7db0d9ecd6cc27c3abc1d0733bc9ed34707cf8ef2',
}
def main():
    root = Path(__file__).resolve().parents[1] / 'App/MapWeb'
    root.mkdir(parents=True, exist_ok=True)
    for name, expected in ASSETS.items():
        output = root / name
        if output.exists() and hashlib.sha256(output.read_bytes()).hexdigest() == expected:
            continue
        url = 'https://unpkg.com/maplibre-gl@5.6.1/' + ('' if name == 'LICENSE.txt' else 'dist/') + name
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('MapLibre asset checksum mismatch: ' + name)
        output.write_bytes(data)
if __name__ == '__main__':
    main()
