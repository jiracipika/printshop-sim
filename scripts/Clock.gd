extends Node3D

## Wall-clock prop (task 12 art pass). Shows the real system time and keeps
## the minute hand crawling so the room has quiet life. Built from primitives;
## no external assets, web-safe.

var _minute_hand: Node3D
var _hour_hand: Node3D


func _ready() -> void:
	var face := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 0.04
	face.mesh = cyl
	face.rotation_degrees = Vector3(90, 0, 0)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color("#EEE5D3")
	face_mat.roughness = 0.8
	face.material_override = face_mat
	add_child(face)

	var rim := MeshInstance3D.new()
	var rim_cyl := TorusMesh.new()
	rim_cyl.inner_radius = 0.15
	rim_cyl.outer_radius = 0.17
	rim.mesh = rim_cyl
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("#202B2B")
	rim_mat.roughness = 0.4
	rim.material_override = rim_mat
	rim.rotation_degrees = Vector3(90, 0, 0)
	rim.position = Vector3(0, 0, 0.015)
	add_child(rim)

	_hour_hand = _hand(0.07, 0.014)
	_minute_hand = _hand(0.12, 0.01)
	_set_hands_from_system_time()


func _hand(length: float, thickness: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 0.03)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Box runs "up" from the pivot; rotation about Z sweeps it like a hand.
	box.size = Vector3(thickness, length, 0.006)
	m.mesh = box
	m.position = Vector3(0, length * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#202B2B")
	m.material_override = mat
	pivot.add_child(m)
	add_child(pivot)
	return pivot


func _set_hands_from_system_time() -> void:
	var t := Time.get_time_dict_from_system()
	var minutes := float(t.minute) + float(t.second) / 60.0
	var hours := fmod(float(t.hour), 12.0) + minutes / 60.0
	_minute_hand.rotation.z = -TAU * minutes / 60.0
	_hour_hand.rotation.z = -TAU * hours / 12.0


func _process(_delta: float) -> void:
	_set_hands_from_system_time()
