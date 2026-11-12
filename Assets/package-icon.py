"""Package PNG representations in Apple's ICNS container."""
from pathlib import Path
import struct
root = Path(__file__).resolve().parent.parent
entries = [('icp4',16), ('icp5',32), ('icp6',64), ('ic07',128), ('ic08',256), ('ic09',512), ('ic10',1024)]
chunks = []
for kind, size in entries:
    name = f'icon_{size}x{size}.png' if size not in (64,1024) else ('icon_32x32@2x.png' if size == 64 else 'icon_512x512@2x.png')
    data = (root / '.build/WorshipFlow.iconset' / name).read_bytes()
    chunks.append(kind.encode() + struct.pack('>I',len(data)+8) + data)
body = b''.join(chunks)
(root / 'WorshipFlow.app/Contents/Resources/WorshipFlow.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
