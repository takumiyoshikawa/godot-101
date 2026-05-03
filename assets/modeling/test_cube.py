"""Pipeline smoke test: emits a 1m cube as GLB.

    .agents/skills/blender-asset/build.sh assets/modeling/test_cube.py
"""

import bmesh
import bpy

from prelude import parse_args, run
from export import save_glb


def main() -> None:
    args = parse_args()

    mesh = bpy.data.meshes.new("TestCube")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("TestCube", mesh)
    bpy.context.scene.collection.objects.link(obj)

    save_glb(args.out)


if __name__ == "__main__":
    run(main)
