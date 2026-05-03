extends SceneTree

# Loads a GLB and renders one frame into a PNG via SubViewport.
#
# Usage:
#   godot --path . --script res://.agents/skills/blender-asset/godot/render_glb.gd \
#         -- <res://path.glb> <absolute_or_res_png>
#
# Note: cannot run with --headless (dummy display server does not render).
# Run with the platform default display driver; on macOS this briefly
# opens a window. Pair with --quit-after if you want a hard upper bound.

const SIZE := Vector2i(960, 540)
const FRAMES := 4
const CAM_POS := Vector3(0.2, 0.32, 1.4)
const CAM_TARGET := Vector3(0.08, 0.0, 0.0)
const CAM_FOV := 38.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: render_glb.gd <res://path.glb> <out.png>")
		quit(1)
		return

	var glb_path: String = args[0]
	var out_png: String = args[1]
	if out_png.begins_with("res://"):
		out_png = ProjectSettings.globalize_path(out_png)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(glb_path), state)
	if err != OK:
		printerr("GLTFDocument.append_from_file failed: ", err)
		quit(1)
		return
	var glb_scene := doc.generate_scene(state)
	if glb_scene == null:
		printerr("generate_scene returned null")
		quit(1)
		return

	var sub := SubViewport.new()
	sub.size = SIZE
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(sub)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.55)
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.7
	sub.add_child(sun)

	sub.add_child(glb_scene)

	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	sub.add_child(cam)
	cam.look_at_from_position(CAM_POS, CAM_TARGET, Vector3.UP)
	cam.make_current()

	for i in FRAMES:
		await self.process_frame

	var img := sub.get_texture().get_image()
	if img == null:
		printerr("SubViewport texture returned null image (display/rendering driver issue?)")
		quit(1)
		return

	# Detect a fully blank/black image — symptom of headless dummy rendering.
	var sample := img.get_pixel(SIZE.x / 2, SIZE.y / 2)
	print("center pixel rgba=", sample)

	var save_err := img.save_png(out_png)
	if save_err != OK:
		printerr("save_png failed: ", save_err, " path=", out_png)
		quit(1)
		return

	print("OK wrote ", out_png, " size=", img.get_size())
	sub.queue_free()
	quit(0)
