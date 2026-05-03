"""Tactical pump-action shotgun (Remington 870 style), full polymer stock.

    .agents/skills/blender-asset/build.sh assets/modeling/shotgun.py

Origin at the receiver center; barrel along +X (muzzle at +X end). All-black
polymer + dark gunmetal. Total length ~0.9m. PS1-era poly count.
"""

from __future__ import annotations

import math

import bmesh
import bpy
import mathutils

from prelude import parse_args, run
from export import save_glb


def _material(name, color, roughness, metallic):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _add(name, bm, material):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _box(size, location):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=location, verts=bm.verts)
    return bm


def _cyl(radius, depth, segments, axis, location):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    # Cylinder is built along local Z. Mark side faces smooth (normals ⟂ Z)
    # and cap faces flat (normals ∥ Z). The Blender→GLB exporter splits the
    # rim verts so smooth/flat boundary stays sharp in Godot.
    for f in bm.faces:
        f.smooth = abs(f.normal.z) < 0.5

    if axis == "x":
        rot = mathutils.Matrix.Rotation(math.pi / 2.0, 4, "Y")
        bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    elif axis == "y":
        rot = mathutils.Matrix.Rotation(math.pi / 2.0, 4, "X")
        bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=location, verts=bm.verts)
    return bm


def _tapered(front_yz, back_yz, length, location):
    """Cuboid with different Y/Z extents at the +X end vs -X end."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    fy, fz = front_yz
    by, bz = back_yz
    for v in bm.verts:
        if v.co.x > 0:
            v.co.y *= fy
            v.co.z *= fz
        else:
            v.co.y *= by
            v.co.z *= bz
        v.co.x *= length
    bmesh.ops.translate(bm, vec=location, verts=bm.verts)
    return bm


def main() -> None:
    args = parse_args()

    polymer = _material("Polymer", (0.045, 0.045, 0.05, 1.0), 0.6, 0.0)
    metal = _material("Metal", (0.06, 0.06, 0.07, 1.0), 0.4, 1.0)
    rubber = _material("Rubber", (0.025, 0.025, 0.025, 1.0), 0.85, 0.0)

    # ---- Receiver ----
    rec_len = 0.14
    rec_w = 0.038
    rec_h = 0.052
    _add("Receiver", _box((rec_len, rec_w, rec_h), (0.0, 0.0, 0.0)), metal)
    rec_front = rec_len / 2.0
    rec_back = -rec_len / 2.0
    rec_top = rec_h / 2.0
    rec_bottom = -rec_h / 2.0

    # ---- Barrel ----
    barrel_len = 0.46
    barrel_r = 0.012
    barrel_z = rec_top - 0.013
    _add("Barrel",
         _cyl(barrel_r, barrel_len, 24, "x",
              (rec_front + barrel_len / 2.0, 0.0, barrel_z)),
         metal)
    muzzle_x = rec_front + barrel_len

    # ---- Magazine tube + cap ----
    mag_len = 0.36
    mag_r = 0.009
    mag_z = barrel_z - 0.022
    _add("MagTube",
         _cyl(mag_r, mag_len, 16, "x",
              (rec_front + mag_len / 2.0, 0.0, mag_z)),
         metal)
    mag_front = rec_front + mag_len
    cap_len = 0.014
    _add("MagCap",
         _cyl(0.012, cap_len, 16, "x",
              (mag_front + cap_len / 2.0, 0.0, mag_z)),
         metal)

    # Barrel-to-magazine support clamp near the front
    _add("BarrelClamp",
         _box((0.018, 0.024, 0.030),
              (mag_front - 0.018, 0.0, (barrel_z + mag_z) / 2.0)),
         metal)

    # ---- Pump (corncob ribbed sleeve around the magazine tube) ----
    # Forward-closed position: pump slid all the way toward the muzzle,
    # leaving room near the receiver for the action travel.
    pump_x_end = mag_front - 0.020
    pump_x_start = pump_x_end - 0.145
    pump_x_center = (pump_x_start + pump_x_end) / 2.0
    pump_len = pump_x_end - pump_x_start
    pump_core_r = 0.018
    pump_rib_r = 0.022

    _add("PumpCore",
         _cyl(pump_core_r, pump_len, 24, "x",
              (pump_x_center, 0.0, mag_z)),
         polymer)

    n_ribs = 9
    rib_width = 0.011
    rib_gap = 0.005
    rib_pitch = rib_width + rib_gap
    span = n_ribs * rib_pitch - rib_gap
    rib_first = pump_x_center - span / 2.0 + rib_width / 2.0
    for i in range(n_ribs):
        rx = rib_first + i * rib_pitch
        _add(f"PumpRib{i}",
             _cyl(pump_rib_r, rib_width, 20, "x",
                  (rx, 0.0, mag_z)),
             polymer)

    # ---- Trigger guard + trigger ----
    tg_len = 0.075
    tg_h = 0.014
    _add("TriggerGuard",
         _box((tg_len, 0.022, tg_h),
              (0.005, 0.0, rec_bottom - tg_h / 2.0)),
         polymer)
    _add("Trigger",
         _box((0.006, 0.008, 0.020),
              (0.005, 0.0, rec_bottom - 0.018)),
         metal)

    # ---- Front sight bead ----
    _add("FrontSight",
         _box((0.014, 0.006, 0.014),
              (muzzle_x - 0.020, 0.0, barrel_z + barrel_r + 0.006)),
         metal)

    # ---- Stock ----
    stock_len = 0.30
    stock_pitch = math.radians(-5.0)
    stock_front_yz = (0.030, 0.044)
    stock_back_yz = (0.046, 0.082)

    stock = _tapered(stock_front_yz, stock_back_yz, stock_len, (0.0, 0.0, 0.0))
    rot = mathutils.Matrix.Rotation(stock_pitch, 4, "Y")
    bmesh.ops.transform(stock, matrix=rot, verts=stock.verts)

    # Anchor +X end of stock at the receiver back, slightly below center.
    stock_front_local = (math.cos(stock_pitch) * stock_len / 2.0,
                         0.0,
                         -math.sin(stock_pitch) * stock_len / 2.0)
    target_front = (rec_back, 0.0, -0.005)
    stock_translate = (target_front[0] - stock_front_local[0],
                       0.0,
                       target_front[2] - stock_front_local[2])
    bmesh.ops.translate(stock, vec=stock_translate, verts=stock.verts)
    _add("Stock", stock, polymer)

    # ---- Buttpad ----
    pad_thick = 0.014
    pad_yz = (0.048, 0.086)
    pad = _tapered(pad_yz, pad_yz, pad_thick, (0.0, 0.0, 0.0))
    bmesh.ops.transform(pad, matrix=rot, verts=pad.verts)

    # Stock back-end (-X) world position, then offset another half-pad along
    # the rotated -X axis.
    stock_back_local = (-math.cos(stock_pitch) * stock_len / 2.0,
                        0.0,
                        math.sin(stock_pitch) * stock_len / 2.0)
    pad_offset = (-math.cos(stock_pitch) * pad_thick / 2.0,
                  0.0,
                  math.sin(stock_pitch) * pad_thick / 2.0)
    pad_world = (stock_translate[0] + stock_back_local[0] + pad_offset[0],
                 0.0,
                 stock_translate[2] + stock_back_local[2] + pad_offset[2])
    bmesh.ops.translate(pad, vec=pad_world, verts=pad.verts)
    _add("Buttpad", pad, rubber)

    save_glb(args.out)


if __name__ == "__main__":
    run(main)
