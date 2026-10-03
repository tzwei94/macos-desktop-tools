#!/usr/bin/env python3
"""Convert committed PNG masters to native ICNS and PNG-compressed ICO files."""
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def resize(source, destination, size):
    subprocess.run(['/usr/bin/sips', '-z', str(size), str(size), str(source),
                    '--out', str(destination)], check=True, stdout=subprocess.DEVNULL)


def convert(directory):
    source = directory / 'icon.png'
    with tempfile.TemporaryDirectory(prefix='desktop-tool-icons-') as temporary:
        temporary = Path(temporary)
        iconset = temporary / 'AppIcon.iconset'
        iconset.mkdir()
        for points in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                suffix = '@2x' if scale == 2 else ''
                resize(source, iconset / f'icon_{points}x{points}{suffix}.png', points * scale)
        subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(iconset), '-o', str(directory / 'AppIcon.icns')], check=True)
        sizes = [16, 32, 48, 64, 128, 256]
        chunks = []
        for size in sizes:
            path = temporary / f'ico-{size}.png'
            resize(source, path, size)
            chunks.append(path.read_bytes())
        offset = 6 + 16 * len(sizes)
        header = struct.pack('<HHH', 0, 1, len(sizes))
        entries = []
        for size, chunk in zip(sizes, chunks):
            entries.append(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(chunk), offset))
            offset += len(chunk)
        (directory / 'AppIcon.ico').write_bytes(header + b''.join(entries) + b''.join(chunks))
    print(f'Created ICNS and ICO: {directory.name}')


if __name__ == '__main__':
    for directory in sorted((ROOT / 'assets/icons').iterdir()):
        if (directory / 'icon.png').exists():
            convert(directory)
