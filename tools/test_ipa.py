from pathlib import Path
import struct
import tempfile
import unittest

from package_ipa import validate_device_binary


class DeviceBinaryTests(unittest.TestCase):
    def test_reject_simulator_even_when_arm64(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / 'App'
            header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
            binary.write_bytes(header + struct.pack('<6I', 0x32, 24, 7, 0, 0, 0))
            with self.assertRaisesRegex(ValueError, 'Not an iOS device'):
                validate_device_binary(binary)
            binary.write_bytes(header + struct.pack('<6I', 0x32, 24, 2, 0, 0, 0))
            validate_device_binary(binary)

    def test_reject_corrupt_load_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / 'App'
            binary.write_bytes(struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0))
            with self.assertRaises(ValueError):
                validate_device_binary(binary)


if __name__ == '__main__':
    unittest.main()
