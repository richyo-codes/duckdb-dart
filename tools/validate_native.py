"""Check mobile architecture/SDK and Android 16 KB load alignment before upload."""
import struct


def validate_library(data, target):
    if target.startswith('android-'):
        if data[:6] != b'\x7fELF\x02\x01':
            raise ValueError('Expected a little-endian ELF64 shared library')
        kind, machine = struct.unpack_from('<HH', data, 16)
        expected = 183 if target.endswith('arm64') else 62
        if kind != 3 or machine != expected:
            raise ValueError(f'Wrong ELF architecture/type for {target}')
        offset = struct.unpack_from('<Q', data, 32)[0]
        entry_size, count = struct.unpack_from('<HH', data, 54)
        loads = 0
        for index in range(count):
            header = offset + index * entry_size
            if struct.unpack_from('<I', data, header)[0] == 1:
                loads += 1
                alignment = struct.unpack_from('<Q', data, header + 48)[0]
                if alignment < 16384:
                    raise ValueError('Android library requires at least 16 KB load alignment')
        if not loads:
            raise ValueError('ELF library has no load segments')
    else:
        magic, cpu, _, kind, count, _, _, _ = struct.unpack_from('<8I', data)
        expected_cpu = 0x0100000C if target.endswith('arm64') else 0x01000007
        if magic != 0xFEEDFACF or cpu != expected_cpu or kind != 6:
            raise ValueError(f'Wrong Mach-O architecture/type for {target}')
        expected_platform = 7 if 'simulator' in target else 2
        offset = 32
        for _ in range(count):
            command, size = struct.unpack_from('<II', data, offset)
            if size < 8 or offset + size > len(data):
                raise ValueError('Invalid Mach-O load command')
            if command == 0x32:  # LC_BUILD_VERSION
                sdk_platform = struct.unpack_from('<I', data, offset + 8)[0]
                if sdk_platform != expected_platform:
                    raise ValueError('iOS device/simulator SDK mismatch')
                return
            offset += size
        raise ValueError('Missing Mach-O LC_BUILD_VERSION')
