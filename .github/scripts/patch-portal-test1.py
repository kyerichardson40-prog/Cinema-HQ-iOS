"""Build an unsigned portal preallocation test IPA; requires the original IPA."""
import sys, struct, uuid, zipfile
from pathlib import Path

source, output = map(Path, sys.argv[1:3])
entry = "Payload/Spiderman.app/Spiderman"
with zipfile.ZipFile(source) as archive:
    original = archive.read(entry)
    assert struct.unpack_from(">I", original, 0)[0] == 0xcafebabe
    offset = None
    for index in range(struct.unpack_from(">I", original, 4)[0]):
        cpu, subtype, start, size, alignment = struct.unpack_from(">5I", original, 8 + 20 * index)
        if cpu == 0x100000c:
            offset = start
    assert offset is not None
    arm64 = original[offset:]
    position = 32
    found_uuid = None
    for _ in range(struct.unpack_from("<I", arm64, 16)[0]):
        command, size = struct.unpack_from("<II", arm64, position)
        if command == 0x1b:
            found_uuid = str(uuid.UUID(bytes=arm64[position+8:position+24]))
        position += size
    assert found_uuid == "135e4f28-1cb4-3ef3-b91d-535bf291409f", found_uuid
    site = 0x5648bc
    target = 0x56a4ec
    expected = struct.pack("<I", 0x94000000 | (((target-site)//4) & 0x3ffffff))
    assert original[offset+site:offset+site+4] == expected
    patched = bytearray(original)
    patched[offset+site:offset+site+4] = bytes.fromhex("1f2003d5")
    with zipfile.ZipFile(output, "w") as result:
        for item in archive.infolist():
            if "/_CodeSignature/" in item.filename or item.filename.endswith("/embedded.mobileprovision"):
                continue
            result.writestr(item, patched if item.filename == entry else archive.read(item.filename))
with zipfile.ZipFile(output) as archive:
    assert archive.read(entry) == patched
    assert archive.testzip() is None
print(output, output.stat().st_size)
