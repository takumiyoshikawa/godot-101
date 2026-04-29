extends SceneTree

const DEFAULT_PORTRAIT_SCENE := "res://addons/dialogic/Modules/Character/default_portrait.tscn"
const CHARACTERS_DIR := "res://features/characters"

func _init() -> void:
	var characters := [
		{
			"id": "Don",
			"display": "Don Vito Catleone",
			"color": Color("d4af37"),
			"image": "res://assets/sprites/characters/don.png",
		},
		{
			"id": "Luca",
			"display": "Luca",
			"color": Color("88c0d0"),
			"image": "res://assets/sprites/characters/luca.png",
		},
		{
			"id": "Tomaso",
			"display": "Tomaso",
			"color": Color("e0a458"),
			"image": "res://assets/sprites/characters/tomaso.png",
		},
	]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHARACTERS_DIR))

	var directory: Dictionary = ProjectSettings.get_setting("dialogic/directories/dch_directory", {})
	for c in characters:
		var save_path := "%s/%s.dch" % [CHARACTERS_DIR, c["id"].to_lower()]
		var ch := DialogicCharacter.new()
		ch.display_name = c["display"]
		ch.color = c["color"]
		ch.scale = 1.0
		ch.offset = Vector2.ZERO
		ch.mirror = false
		ch.default_portrait = "neutral"
		ch.portraits = {
			"neutral": {
				"scene": DEFAULT_PORTRAIT_SCENE,
				"export_overrides": {
					"image": "\"%s\"" % c["image"],
				},
			},
		}
		var serialized := var_to_str(inst_to_dict(ch))
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		if file == null:
			printerr("failed to open %s for write: %s" % [save_path, FileAccess.get_open_error()])
			quit(1)
			return
		file.store_string(serialized)
		file.close()
		print("SAVED: ", save_path)
		directory[c["id"]] = save_path

	ProjectSettings.set_setting("dialogic/directories/dch_directory", directory)
	var save_err := ProjectSettings.save()
	if save_err != OK:
		printerr("ProjectSettings.save failed: ", save_err)
		quit(1)
		return
	print("DCH_DIRECTORY: ", directory)
	quit(0)
