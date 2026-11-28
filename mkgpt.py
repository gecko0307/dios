#!/usr/bin/env python3
"""Wrap a bare FAT image (e.g. from fstool) into a GPT disk with one EFI System Partition.

Usage: python mkgpt.py disk.img disk_gpt.img [--start 2048] [--no-patch-hidden]
"""
import argparse
import os
import struct
import uuid
import zlib

SECTOR = 512
ENTRIES = 128
ENTRY_SIZE = 128
ENTRY_SECTORS = ENTRIES * ENTRY_SIZE // SECTOR  # 32
ESP_TYPE = uuid.UUID("C12A7328-F81F-11D2-BA4B-00A0C93EC93B")
BIOS_TYPE = uuid.UUID("21686148-6449-6E6F-744E-656564454649")


def crc32(b):
    return zlib.crc32(b) & 0xFFFFFFFF


def header(cur, backup, first_usable, last_usable, disk_guid, entries_lba, entries_crc):
    h = struct.pack(
        "<8sIIIIQQQQ16sQIII",
        b"EFI PART", 0x00010000, 92, 0, 0,
        cur, backup, first_usable, last_usable,
        disk_guid.bytes_le, entries_lba, ENTRIES, ENTRY_SIZE, entries_crc,
    )
    h = h[:16] + struct.pack("<I", crc32(h)) + h[20:]  # header CRC computed with CRC field = 0
    return h.ljust(SECTOR, b"\0")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fat_image")
    ap.add_argument("output")
    ap.add_argument("--start", type=int, default=None,
                    help="ESP start LBA (default 2048)")
    ap.add_argument("--bios-part", action="store_true",
                    help="also create a 1 MiB BIOS boot partition (EF02) as partition 2, after the ESP")
    ap.add_argument("--no-patch-hidden", action="store_true",
                    help="don't update the FAT32 'hidden sectors' BPB field")
    a = ap.parse_args()

    fat_size = os.path.getsize(a.fat_image)
    part_sectors = (fat_size + SECTOR - 1) // SECTOR
    start = a.start if a.start is not None else 2048
    part_end = start + part_sectors - 1

    # backup entries (32 sectors) + backup header (1 sector) after the partition; round up to 1 MiB
    bios_first = (part_end + 1 + 2047) // 2048 * 2048   # 1 MiB aligned, right after the ESP
    used_end = bios_first + 2048 if a.bios_part else start + part_sectors
    total = used_end + ENTRY_SECTORS + 1
    total = (total + 2047) // 2048 * 2048
    last = total - 1
    first_usable = 2 + ENTRY_SECTORS          # 34
    last_usable = last - ENTRY_SECTORS - 1    # last - 33

    disk_guid = uuid.uuid4()
    def pentry(ptype, first, last_lba, name):
        return struct.pack("<16s16sQQQ72s", ptype.bytes_le, uuid.uuid4().bytes_le,
                           first, last_lba, 0, name.encode("utf-16-le"))

    parts = [pentry(ESP_TYPE, start, part_end, "EFI System")]          # partition 1
    if a.bios_part:
        parts.append(pentry(BIOS_TYPE, bios_first, bios_first + 2047, "BIOS boot"))  # partition 2
    entries = b"".join(parts).ljust(ENTRIES * ENTRY_SIZE, b"\0")
    ecrc = crc32(entries)

    # protective MBR
    mbr = bytearray(SECTOR)
    mbr[446:462] = struct.pack("<B3sB3sII", 0x00, b"\x00\x02\x00", 0xEE, b"\xFF\xFF\xFF",
                               1, min(total - 1, 0xFFFFFFFF))
    mbr[510:512] = b"\x55\xAA"

    primary = header(1, last, first_usable, last_usable, disk_guid, 2, ecrc)
    backup = header(last, 1, first_usable, last_usable, disk_guid, last - ENTRY_SECTORS, ecrc)

    with open(a.output, "wb") as out:
        out.truncate(total * SECTOR)
        out.seek(0);                      out.write(mbr)
        out.seek(1 * SECTOR);             out.write(primary)
        out.seek(2 * SECTOR);             out.write(entries)
        out.seek(start * SECTOR)
        with open(a.fat_image, "rb") as f:
            while chunk := f.read(1 << 20):
                out.write(chunk)
        out.seek((last - ENTRY_SECTORS) * SECTOR); out.write(entries)
        out.seek(last * SECTOR);          out.write(backup)

        if not a.no_patch_hidden:
            with open(a.fat_image, "rb") as f:
                boot = f.read(SECTOR)
            if boot[510:512] == b"\x55\xAA":
                out.seek(start * SECTOR + 28)
                out.write(struct.pack("<I", start))
                # FAT32 backup boot sector (BPB_BkBootSec at offset 50)
                bk = struct.unpack_from("<H", boot, 50)[0]
                if bk:
                    out.seek((start + bk) * SECTOR + 28)
                    out.write(struct.pack("<I", start))

    print(f"{a.output}: {total} sectors ({total * SECTOR // (1 << 20)} MiB), "
          f"ESP LBA {start}..{part_end}, disk GUID {disk_guid}")


if __name__ == "__main__":
    main()
