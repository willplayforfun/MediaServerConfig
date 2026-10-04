# PGS Subtitle OCR Conversion

## The Problem

Blu-ray rips often contain subtitles encoded as PGS (Presentation Graphic Stream) — image-based tracks
rather than text. Most players and clients can render these fine, but they cause friction:

- Plex and Jellyfin must transcode the video stream to burn them in for clients that can't render PGS
- Search, copy, and accessibility features don't work on image-based tracks
- External subtitle tools can't sync, edit, or re-time them

Converting PGS to SRT via OCR makes subtitles universally compatible and eliminates forced transcoding.

---

## What Won't Work

**Bazarr** — already in the stack, and looked like the obvious answer. Its "Embedded Subtitles"
feature only handles text-based tracks (SRT, ASS, SSA). It explicitly does not support PGS OCR,
the maintainers have ruled it out, and the `linuxserver/bazarr` image doesn't include Tesseract.

---

## Promising Paths

### FileFlows + pgsrip

**FileFlows** (`revenz/fileflows`) is a media processing platform with exactly the workflow UI
described: a queue, per-file manual triggering, enable/disable automation, and a visual flow builder.
It runs as a server (UI + queue) plus one or more worker nodes that process files.

FileFlows can extract PGS tracks to `.sup` files, but has no native OCR step. The OCR itself needs
a dedicated tool.

**pgsrip** (`ratoaq2/pgsrip`) is a Python CLI that converts PGS/SUP to SRT using Tesseract OCR.
It runs headlessly and is a natural fit as the worker step in a FileFlows custom script flow.

The combined pipeline would be:
```
FileFlows scans library
  → identifies files with PGS tracks but no text subtitles
  → runs pgsrip via custom script step
  → pgsrip writes .srt alongside the MKV
```

**What we don't know yet:**
- Whether FileFlows supports subpath proxying cleanly at e.g. `/fileflows` (expected yes, standard port 5000)
- How to wire pgsrip as a Docker sidecar or script step within a FileFlows flow
- Queue behavior and resource limits for a CPU-heavy OCR workload
- Whether pgsrip handles multi-language PGS tracks gracefully

### Other OCR Tools (not yet evaluated)

- **Suptext** — Go binary + Tesseract, similar to pgsrip. May be simpler to containerize.
- **Subtitle Edit** — Has a batch CLI mode and strong OCR; primarily a Windows GUI app so containerization is awkward.

---

## Recommended Next Step

Stand up FileFlows and validate that a custom script step can invoke pgsrip against a test file
before committing to the full integration.
