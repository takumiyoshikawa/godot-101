# godot-101

Godot 4.6 game project. Headless development workflow rules live in
`.agents/skills/headless-godot/SKILL.md`; read that before running Godot CLI.

## Build

```bash
tools/rebuild_web.sh
```

Runs smoke → tests → Web export. Output lands in `build/web/`.

## Serve locally

```bash
python3 -m http.server --directory build/web 8000
# → http://localhost:8000/
```

`file://` does not work for Web exports; serve over HTTP.
