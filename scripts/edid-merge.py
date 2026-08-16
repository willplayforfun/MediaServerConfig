#!/usr/bin/env python3
"""
edid-merge.py

Builds a hybrid EDID: keeps the video timing / base block from a
known-working source EDID (e.g. what a wireless HDMI transmitter currently
advertises) untouched, and only splices in the CTA-861 audio capability
block (Basic Audio flag + Short Audio Descriptors) from a known-good-audio
source EDID (e.g. a real display's captured EDID). This fixes missing audio
capability advertisement without changing anything about video negotiation
that's already working.

Usage:
    python3 edid-merge.py --video transmitter.bin --audio real-display.bin --output hybrid.bin

--video   EDID to keep as the source of truth for everything except audio.
--audio   EDID to pull the Audio Data Block (SADs) from.
--output  where to write the merged result.

Only supports a single (or zero) CTA-861 extension block in --video; other
extension types, or more than one extension block, are rejected rather than
silently mishandled.
"""

import argparse
import sys

EDID_BLOCK_SIZE = 128
EDID_HEADER = bytes([0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0])
CTA_TAG = 0x02
AUDIO_DB_TAG = 1
BASIC_AUDIO_BIT = 0b01000000


def checksum(block):
    return (-sum(block[:127])) & 0xFF


def validate_edid(data, label):
    if len(data) < EDID_BLOCK_SIZE or len(data) % EDID_BLOCK_SIZE != 0:
        sys.exit(f"error: {label} is not a valid EDID size ({len(data)} bytes)")
    if data[:8] != EDID_HEADER:
        sys.exit(f"error: {label} doesn't start with the EDID magic header - "
                  f"is this actually a raw EDID dump?")
    for i in range(0, len(data), EDID_BLOCK_SIZE):
        block = data[i:i + EDID_BLOCK_SIZE]
        if sum(block) & 0xFF != 0:
            sys.exit(f"error: {label} block {i // EDID_BLOCK_SIZE} fails its "
                      f"checksum - capture may be corrupt")


def parse_cta_data_blocks(ext):
    """Returns (dtd_offset, flags_byte, [(tag, payload_bytes), ...])."""
    dtd_offset = ext[2]
    flags = ext[3]
    blocks = []
    pos = 4
    while pos < dtd_offset:
        header = ext[pos]
        tag = header >> 5
        length = header & 0x1F
        payload = bytes(ext[pos + 1: pos + 1 + length])
        blocks.append((tag, payload))
        pos += 1 + length
    return dtd_offset, flags, blocks


def find_audio_sads(edid):
    """Pulls the Audio Data Block payload out of edid's CTA-861 extension."""
    if len(edid) < EDID_BLOCK_SIZE * 2:
        sys.exit("error: --audio source has no extension block - no audio "
                  "capability to copy from it")
    ext = edid[EDID_BLOCK_SIZE:EDID_BLOCK_SIZE * 2]
    if ext[0] != CTA_TAG:
        sys.exit("error: --audio source's extension isn't a CTA-861 extension")
    _, _, blocks = parse_cta_data_blocks(ext)
    for tag, payload in blocks:
        if tag == AUDIO_DB_TAG:
            return payload
    sys.exit("error: --audio source has a CTA-861 extension but no Audio "
              "Data Block in it - nothing to copy")


def build_hybrid(video_edid, audio_sads):
    if len(video_edid) > EDID_BLOCK_SIZE * 2:
        sys.exit("error: --video source has more than one extension block - "
                  "not supported (would risk silently dropping data)")

    base = bytearray(video_edid[:EDID_BLOCK_SIZE])
    has_ext = base[126] > 0

    if has_ext:
        ext_in = video_edid[EDID_BLOCK_SIZE:EDID_BLOCK_SIZE * 2]
        if ext_in[0] != CTA_TAG:
            sys.exit("error: --video's extension isn't a CTA-861 extension; "
                      "this tool only knows how to merge into that type")
        dtd_offset, flags, blocks = parse_cta_data_blocks(ext_in)
        if any(tag == AUDIO_DB_TAG for tag, _ in blocks):
            print("note: --video already advertises an Audio Data Block; "
                  "leaving its SADs alone, only ensuring Basic Audio is set.")
        else:
            blocks = [(AUDIO_DB_TAG, audio_sads)] + blocks
        revision = ext_in[1]
        # Trailing zero padding after the last real DTD is extremely common
        # (extensions rarely fill every DTD slot) and doesn't need to be
        # preserved explicitly - the destination is already zero-filled
        # there by default, so stripping it frees up real space for the
        # inserted audio block instead of it counting against the budget.
        dtds_and_tail = bytes(ext_in[dtd_offset:126]).rstrip(b"\x00")
    else:
        flags = 0
        blocks = [(AUDIO_DB_TAG, audio_sads)]
        revision = 3
        dtds_and_tail = b""

    collection = bytearray()
    for tag, payload in blocks:
        collection.append((tag << 5) | len(payload))
        collection.extend(payload)

    new_dtd_offset = 4 + len(collection)
    end = new_dtd_offset + len(dtds_and_tail)
    if end > 126:
        sys.exit(f"error: merged data doesn't fit in one extension block "
                  f"({end} bytes needed, 126 available) - try a --audio "
                  f"source with fewer audio formats")

    new_ext = bytearray(EDID_BLOCK_SIZE)
    new_ext[0] = CTA_TAG
    new_ext[1] = revision
    new_ext[2] = new_dtd_offset
    new_ext[3] = flags | BASIC_AUDIO_BIT
    new_ext[4:4 + len(collection)] = collection
    new_ext[new_dtd_offset:new_dtd_offset + len(dtds_and_tail)] = dtds_and_tail
    new_ext[127] = checksum(new_ext)

    if base[126] == 0:
        base[126] = 1
    base[127] = checksum(base)

    return bytes(base) + bytes(new_ext)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--video", required=True,
                     help="EDID to keep as-is for video timings/base block")
    ap.add_argument("--audio", required=True,
                     help="EDID to copy the real Audio Data Block (SADs) from")
    ap.add_argument("--output", required=True, help="path to write the merged EDID")
    args = ap.parse_args()

    with open(args.video, "rb") as f:
        video_edid = f.read()
    with open(args.audio, "rb") as f:
        audio_edid = f.read()

    validate_edid(video_edid, args.video)
    validate_edid(audio_edid, args.audio)

    audio_sads = find_audio_sads(audio_edid)

    result = build_hybrid(video_edid, audio_sads)
    validate_edid(result, "merged result")

    with open(args.output, "wb") as f:
        f.write(result)

    print(f"Wrote {len(result)}-byte hybrid EDID to {args.output}")
    print(f"  video/base block: unchanged from {args.video}")
    print(f"  audio formats copied: {len(audio_sads) // 3} (from {args.audio})")


if __name__ == "__main__":
    main()
