#!/usr/bin/env python3
"""Packs an extension folder as a CRX3 file, signed with a new RSA key, for the
runtime suite's install dialog. Uses only the standard library and openssl.

    make-crx.py <extension folder> <output.crx>
"""

import hashlib
import io
import os
import struct
import subprocess
import sys
import tempfile
import zipfile


def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def field(number, data):
    """A length-delimited protobuf field."""
    return varint(number << 3 | 2) + varint(len(data)) + data


def archive(folder):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for parent, _, names in sorted(os.walk(folder)):
            for name in sorted(names):
                path = os.path.join(parent, name)
                zip_file.write(path, os.path.relpath(path, folder))
    return buffer.getvalue()


def openssl(*arguments, data=None):
    return subprocess.run(["openssl", *arguments], input=data, capture_output=True, check=True).stdout


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    folder, output = sys.argv[1], sys.argv[2]
    if not os.path.isfile(os.path.join(folder, "manifest.json")):
        sys.exit(f"make-crx.py: no manifest.json in {folder}")

    zip_data = archive(folder)
    with tempfile.TemporaryDirectory() as scratch:
        key = os.path.join(scratch, "key.pem")
        openssl("genrsa", "-out", key, "2048")
        public_key = openssl("rsa", "-in", key, "-pubout", "-outform", "DER")
        # SignedData: the CRX ID, the first 16 bytes of the key's SHA-256.
        signed_data = field(1, hashlib.sha256(public_key).digest()[:16])
        signed = b"CRX3 SignedData\x00" + struct.pack("<I", len(signed_data)) + signed_data + zip_data
        signature = openssl("dgst", "-sha256", "-sign", key, data=signed)

    # CrxFileHeader: sha256_with_rsa = 2, signed_header_data = 10000.
    header = field(2, field(1, public_key) + field(2, signature)) + field(10000, signed_data)
    with open(output, "wb") as crx:
        crx.write(b"Cr24" + struct.pack("<II", 3, len(header)) + header + zip_data)


if __name__ == "__main__":
    main()
