# Guidance for Claude

- Never `git commit` or push unless explicitly asked. Leave changes uncommitted.
- Make all file edits directly with the file editing tools (Edit/Write). Don't edit files through bash, sed, Python or similar scripts.
- Don't use auto memory. Record durable learnings in `agent_guidance/`.
- Claude can't reach the server. Hand the user commands to run (one per fenced `bash` block) and work from the output they paste back.

## Comments

- Write the minimum that orients a reader, plus any non-obvious gotchas: why something must be done a certain way, or what breaks without it.
- Don't explain what the code or config already says, give background on the technology, or list per-item details (packages, devices, flags) unless one of them is a gotcha.
- Say each thing once. Don't repeat what another file, `docs/` or `agent_guidance/` covers.
- Use plain language. Prefer a short inline comment on the line it explains over a paragraph above the block.
- Script headers: one line on what the script does, how to recognise the problem it fixes (if any), and usage.
- Comments written into `.env` and on-screen prompts are user documentation: keep them, but brief.

## Guidance docs

- [Working environment](agent_guidance/environment.md): dev machine, server, deployment
- [Repo layout](agent_guidance/repo-layout.md): where things live, adding a service, planned restructuring
- [Display and HDMI audio](agent_guidance/display-and-hdmi-audio.md): wireless transmitter overheating, the HDMI audio boot race
- [TV launcher](agent_guidance/tv-launcher.md): the smart-TV setup being built
