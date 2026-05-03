extends SceneTree

func _init() -> void:
	var root := Node3D.new()
	root.name = "ShotgunView"
	root.set_script(load("res://shotgun_view.gd"))

	var packed := PackedScene.new()
	var result := packed.pack(root)
	if result != OK:
		printerr("pack failed: ", result)
		quit(1)
		return

	var save_result := ResourceSaver.save(packed, "res://shotgun_view.tscn")
	if save_result != OK:
		printerr("save failed: ", save_result)
		quit(1)
		return

	print("shotgun_view.tscn created")
	quit(0)
