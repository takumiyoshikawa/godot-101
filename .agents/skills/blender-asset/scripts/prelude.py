"""Common bootstrap for Blender-driven asset scripts.

Idiomatic usage in a project script under `assets/modeling/`:

    import bmesh, bpy
    from prelude import parse_args, run
    from export import save_glb

    def main():
        args = parse_args()
        # ... build geometry on bpy.data / bmesh ...
        save_glb(args.out)

    if __name__ == "__main__":
        run(main)

`run(main)` empties the scene and forces a non-zero exit code on
uncaught exceptions (Blender otherwise silently returns 0).
"""

from __future__ import annotations

import argparse
import sys
import traceback

import bpy


def setup() -> None:
    """Reset Blender to an empty scene (no default cube/light/camera)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _argv_after_dashes() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args(extra_args: dict | None = None) -> argparse.Namespace:
    """Parse args after `--` from the Blender CLI invocation.

    Always provides `--out <path>` (the GLB destination).
    Pass `extra_args={'name': {...argparse kwargs}}` to add custom flags.
    """
    p = argparse.ArgumentParser(prog="blender-asset")
    p.add_argument("--out", required=True, help="Output GLB path (absolute).")
    if extra_args:
        for name, kwargs in extra_args.items():
            flag = name if name.startswith("--") else f"--{name}"
            p.add_argument(flag, **kwargs)
    return p.parse_args(_argv_after_dashes())


def run(main_fn) -> None:
    """Entry-point wrapper: setup + run + force non-zero exit on errors.

    Without this wrapper, an uncaught Python exception inside a
    `blender --background --python` script still results in exit code 0,
    which silently breaks build pipelines.
    """
    try:
        setup()
        main_fn()
    except SystemExit:
        raise
    except BaseException as e:
        print(f"[blender-asset] FAILED: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
