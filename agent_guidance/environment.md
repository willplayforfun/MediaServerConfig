# Working environment

## Dev machine

- Windows, with the repo at `M:\Github\MediaServerConfig`.
- No Python installed, so do edits with the file tools or bash, not Python scripts.

## Server

- Runs OpenMediaVault on Debian 13. The repo is deployed to `/opt/docker` and updated with `git pull`.
- Kernel is 7.0 from trixie-backports (`linux-image-amd64`). The 6.12 kernels are still installed as a fallback.
- Intel Skylake iGPU (i915, device 1912) with a single HDMI output, `card0-HDMI-A-1`.
- HDA audio is `card1` (`PCH`). The HDMI codec is `codec#2`, and the connected port is pin `0x07`.

## Working with the server

- Claude has no access. The user runs commands and pastes back the output.
- For diagnosis, prefer a read-only script in `host/` that the user runs once and pastes back (e.g. `host/display-diagnose.sh`) over a long list of commands.
