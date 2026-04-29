---
name: image-asset
description: "Generate or edit a raster image asset for this Godot project (sprites, textures, character art, mockups, transparent cutouts) by delegating to codex's built-in imagegen skill via `codex exec`. Use whenever the user asks for a generated bitmap that should land in the repo (e.g. under `asset/`). Do not substitute SVG/CSS placeholders, and do not try to draw the asset by hand."
---

This repo has no in-process raster image generator. Image generation is delegated to the `codex` CLI, which ships a built-in `imagegen` skill at `$CODEX_HOME/skills/.system/imagegen/SKILL.md`. Drive it with `codex exec` directly — no wrapper script.

## When to use
- User asks for a generated raster asset: dot-e / pixel-art character, sprite, tile, texture, raster icon, banner, mockup, concept art, transparent cutout.
- The output should land in this repo (typically `asset/`).

## When NOT to use
- The user wants vector/SVG output, or wants to extend an existing SVG/icon system in the repo (edit it directly instead).
- The user only wants a quick preview with no project file. Then run `codex exec --full-auto "<prompt>"` and render inline; do not save into the workspace.
- The user explicitly asked for a different tool/API.

## How to invoke

Run `codex exec` non-interactively from the repo root with `--full-auto` (sandboxed workspace-write, so codex can drop the file into the repo) and capture the final message:

```bash
codex exec \
  --full-auto \
  -C "$(pwd)" \
  --color never \
  -o logs/imagegen.last \
  "$(cat <<'PROMPT'
Generate a raster image using the built-in imagegen skill (default built-in tool mode).

User request:
<USER PROMPT GOES HERE — pass through verbatim plus any concrete constraints
 such as style, palette, size, transparency>

After generation, copy or move the final selected image into this exact workspace path:
<ABSOLUTE DESTINATION PATH, e.g. /Users/.../godot-101/asset/dot_character.png>

Rules:
- Use the built-in image_gen path. Do not switch to the CLI fallback (gpt-image-1.5) unless the request truly requires native transparency and you have asked the user.
- For transparent-background requests, follow the standard chroma-key + remove_chroma_key.py flow described in the imagegen skill.
- Do NOT overwrite an existing file at the destination. If one exists, save a sibling versioned filename (e.g. foo-v2.png) and use that path instead.
- Ensure parent directories exist (mkdir -p as needed).
- When done, print exactly one line as the last line of your final message:
  SAVED: <absolute path of the saved image>
PROMPT
)" 2>&1 | tee logs/imagegen.log
```

Then verify and report:

```bash
grep -E '^SAVED: ' logs/imagegen.last | tail -n1 | sed 's/^SAVED: //'
```

If the resulting path exists, report it to the user. Otherwise read `logs/imagegen.log` to see what codex did and retry.

## Picking the destination
- Default to `asset/<slug>.png` where `<slug>` is a short, descriptive, kebab-case name derived from the request (e.g. `asset/dot_character.png`, `asset/parchment_tile.png`).
- Use a subdirectory when it fits the project layout (`asset/textures/...`, `asset/ui/...`).
- Use absolute paths in the codex prompt (avoid relying on codex's CWD interpretation).

## Rules
- Run from the repo root. `-C "$(pwd)"` keeps codex's workspace-write sandbox pinned to this project.
- Do not pass `--dangerously-bypass-approvals-and-sandbox`. `--full-auto` is enough.
- Never silently downgrade to the CLI fallback (`gpt-image-1.5`). The built-in path handles transparent backgrounds via chroma-key + `remove_chroma_key.py` already. If a request genuinely needs native transparency, ask the user before switching.
- For multiple distinct assets, run `codex exec` once per asset. Do not request `n` variants of the same prompt as a substitute for distinct assets.
- Always `mkdir -p logs` before the call so `tee logs/imagegen.log` and `-o logs/imagegen.last` succeed.

## Out of scope
- Editing `.tscn` files to wire the asset into a scene — see `.agents/skills/headless-godot/skills/scene_editing_via_godot.md`.
- Vector/SVG generation, code-driven icons, or in-Godot procedural textures.
- Audio, fonts, or any non-image asset.
