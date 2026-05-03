extends SceneTree

# Loads a GLB at the given res:// path, instantiates it, and reports mesh stats.
# Usage:
#   godot --headless --path . --script res://tools/tests/check_glb.gd -- res://assets/models/test_cube.glb

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: check_glb.gd <res://path/to/model.glb>")
		quit(1)
		return
	var glb_path: String = args[0]

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(glb_path), state)
	if err != OK:
		printerr("GLTFDocument.append_from_file failed: ", err, " for ", glb_path)
		quit(1)
		return

	var scene := doc.generate_scene(state)
	if scene == null:
		printerr("generate_scene returned null")
		quit(1)
		return

	var mesh_count := _count_meshes(scene)
	print("OK glb=", glb_path,
		" nodes=", _count_nodes(scene),
		" mesh_instances=", mesh_count)
	scene.free()
	quit(0)

func _count_nodes(n: Node) -> int:
	var c := 1
	for child in n.get_children():
		c += _count_nodes(child)
	return c

func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for child in n.get_children():
		c += _count_meshes(child)
	return c
