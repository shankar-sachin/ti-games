"""
    [0:8]    "**TI83F*" signature (yes, still used for 84 series)
    [8:11]   three "extra" bytes (usually \\x1A\\x0A\\x00)
    [11:53]  42-byte comment field, null-padded
    [53:55]  length of the data section that follows (uint16 LE)
    [55:57]  variable type flag (0x06 for a program, 0x0D if it's protected)
    [57:65]  8-byte program name, null/0x00-padded
    [65:66]  version byte
    [66:67]  flag byte
    [67:69]  length of the tokenized program body (uint16 LE), repeated
    [69:...] the actual tokenized program bytes
    [-2:]    2-byte checksum (sum of all bytes from offset 55 onward, mod 65536)
"""

import struct

SIGNATURE = b"**TI83F*"
DEFAULT_EXTRA = b"\x1A\x0A\x00"
COMMENT_LEN = 42
NAME_LEN = 8

TYPE_PROGRAM = 0x06
TYPE_PROTECTED_PROGRAM = 0x0D


class EightXPFile:
    """Represents a parsed (or about-to-be-written) .8xp program file."""

    def __init__(self, name, body=b"", comment="", protected=False):
        self.name = name.upper()[:NAME_LEN]
        self.body = body  # raw tokenized bytes
        self.comment = comment[:COMMENT_LEN]
        self.protected = protected

    # ---------- reading ----------

    @classmethod
    def from_bytes(cls, data):
        if data[0:8] != SIGNATURE:
            raise ValueError("Not a valid .8xp file (bad signature)")

        comment = data[11:53].split(b"\x00")[0].decode("ascii", "ignore")
        var_type = data[55]
        name = data[57:57 + NAME_LEN].split(b"\x00")[0].decode("ascii", "ignore")
        body_len = struct.unpack("<H", data[67:69])[0]
        body = data[69:69 + body_len]

        return cls(
            name=name,
            body=body,
            comment=comment,
            protected=(var_type == TYPE_PROTECTED_PROGRAM),
        )

    @classmethod
    def from_file(cls, path):
        with open(path, "rb") as f:
            return cls.from_bytes(f.read())

    # ---------- writing ----------

    def to_bytes(self):
        var_type = TYPE_PROTECTED_PROGRAM if self.protected else TYPE_PROGRAM

        comment_field = self.comment.encode("ascii", "ignore").ljust(COMMENT_LEN, b"\x00")
        name_field = self.name.encode("ascii", "ignore").ljust(NAME_LEN, b"\x00")

        body_len = len(self.body)
        # the "data section" is everything from var_type onward through the body
        data_section = (
            bytes([var_type])
            + b"\x00"  # placeholder flag byte before name, per format
            + name_field
            + b"\x00"  # version byte
            + b"\x00"  # flag byte
            + struct.pack("<H", body_len)
            + self.body
        )

        header = (
            SIGNATURE
            + DEFAULT_EXTRA
            + comment_field
            + struct.pack("<H", len(data_section))
        )

        payload = header + data_section
        checksum = sum(data_section) & 0xFFFF
        return payload + struct.pack("<H", checksum)

    def to_file(self, path):
        with open(path, "wb") as f:
            f.write(self.to_bytes())

    def __repr__(self):
        return f"<EightXPFile name={self.name!r} bytes={len(self.body)} protected={self.protected}>"


def load(path):
    """Shortcut: load an .8xp file from disk."""
    return EightXPFile.from_file(path)


def save(name, body, path, comment="", protected=False):
    """Shortcut: build and save a new .8xp file."""
    EightXPFile(name=name, body=body, comment=comment, protected=protected).to_file(path)
