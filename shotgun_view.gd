extends Node3D

const GLB_PATH := "res://assets/models/shotgun.glb"
const SPIN_SPEED := 0.6  # rad/s

var _pivot: Node3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.78, 0.80)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.90)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 2.0
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.7
	add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.30, 1.5), Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.make_current()

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	var packed: PackedScene = load(GLB_PATH) as PackedScene
	if packed == null:
		push_error("failed to load %s" % GLB_PATH)
		return
	var inst := packed.instantiate()
	# Offset so the gun's geometric midpoint sits on the pivot origin
	# (origin is at the receiver, which is roughly 0.08m back of midpoint).
	inst.position = Vector3(-0.08, 0.0, 0.0)
	_pivot.add_child(inst)


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotate_y(SPIN_SPEED * delta)
