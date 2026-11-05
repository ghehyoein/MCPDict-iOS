"""Package a verified arm64 iOS-device .app for LOCAL re-signing, not direct install."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def validate_device_binary(path: Path):
    with path.open('rb') as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError('Truncated Mach-O header')
        magic, cpu, _, filetype, count, command_size, _, _ = struct.unpack('<8I', header)
        if magic != 0xfeedfacf or cpu != 0x100000c or filetype != 2:
            raise ValueError('Expected a thin arm64 Mach-O executable')
        if command_size > 16_000_000:
            raise ValueError('Invalid Mach-O command size')
        commands = stream.read(command_size)
    offset = 0
    platform = None
    for _ in range(count):
        if offset + 8 > len(commands):
            raise ValueError('Truncated load command')
        cmd, size = struct.unpack_from('<II', commands, offset)
        if size < 8 or offset + size > len(commands):
            raise ValueError('Invalid load command')
        if cmd == 0x32 and size >= 24:  # LC_BUILD_VERSION
            platform = struct.unpack_from('<I', commands, offset + 8)[0]
        offset += size
    if platform != 2:  # PLATFORM_IOS; 7 is iOS Simulator
        raise ValueError(f'Not an iOS device binary: platform={platform}')


def package(app: Path, output: Path):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('App must target iPhoneOS, not the simulator')
    executable = info['CFBundleExecutable']
    if Path(executable).name != executable:
        raise ValueError('Invalid executable path')
    validate_device_binary(app / executable)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(app.rglob('*')):
            if file.is_symlink():
                raise ValueError('Unexpected app symlink')
            if file.is_file():
                archive.write(file, Path('Payload') / app.name / file.relative_to(app))
    with output.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    report = {'bundleIdentifier': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
              'build': info['CFBundleVersion'], 'minimumOSVersion': info['MinimumOSVersion'],
              'platform': 'iPhoneOS', 'architecture': 'arm64', 'signed': False,
              'requiresLocalSigning': True, 'sha256': digest, 'size': output.stat().st_size}
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    output.with_suffix('.sha256').write_text(f'{digest}  {output.name}\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(package(args.app, args.output), indent=2))
