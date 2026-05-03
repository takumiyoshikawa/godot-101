"""GLB export wrapper with project-standard defaults."""

from __future__ import annotations

import os

import bpy


def save_glb(out_path: str) -> None:
    """Export the current scene as GLB to `out_path`.

    Defaults chosen to match what Godot/Unity importers expect:
    - `export_format='GLB'`   single binary file
    - `export_apply=True`     bake modifiers into the mesh (otherwise
                              Subdivide/Decimate/Bevel do not land in the file)
    - `export_yup=True`       glTF convention; matches Godot import default
    - `check_existing=False`  always overwrite

    The destination directory is created if missing.
    """
    out_path = os.path.abspath(out_path)
    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        export_apply=True,
        export_yup=True,
        check_existing=False,
    )
    print(f"[blender-asset] wrote {out_path}")
