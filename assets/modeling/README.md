# assets/modeling/

Project-specific Blender Python scripts that emit `.glb` 3D assets headlessly.

## Build a single asset

```bash
.agents/skills/blender-asset/build.sh assets/modeling/<name>.py
```

The wrapper:
1. Sets `PYTHONPATH` so the script can `from prelude import …` / `from export import …` (helpers under `.agents/skills/blender-asset/scripts/`).
2. Runs `blender --background --python <script> -- --out assets/models/<name>.glb`.
3. Logs to `logs/build_asset_<name>.log`.

Output `.glb` lands at `assets/models/<name>.glb`; Godot picks it up on next editor refresh / build.

## Writing a new script

Use `test_cube.py` as the template:

```python
import bmesh, bpy
from prelude import parse_args, run
from export import save_glb

def main():
    args = parse_args()
    # ... build geometry on bpy.data / bmesh ...
    save_glb(args.out)

if __name__ == "__main__":
    run(main)
```

Idioms (see `.agents/skills/blender-asset/SKILL.md` for the full list):

- Use `bpy.data.*` and `bmesh.ops.*`, **not** `bpy.ops.*`. Operators require a UI context that does not exist under `--background` and fail with "Operator … poll() failed".
- `run(main)` resets the scene first and forces `sys.exit(1)` on uncaught exceptions (Blender otherwise returns 0 even on Python errors).
- `save_glb(out)` applies modifiers and converts Z-up → Y-up automatically.

## Custom flags

If a script needs extra parameters beyond `--out`, declare them via `parse_args`:

```python
args = parse_args({
    "scale": {"type": float, "default": 1.0},
    "seed":  {"type": int, "default": 0},
})
# args.out, args.scale, args.seed
```

Then invoke:

```bash
.agents/skills/blender-asset/build.sh assets/modeling/foo.py --scale 0.7 --seed 42
```
