class_name DayNightCycle
extends Node
const GameSession = preload("res://scripts/core/game_session.gd")
## Controls dynamic Day/Night cycle, rotating SunLight and blending sky/ambient/fog colors.
## Press [T] to fast-forward time by +2.5 hours.

@export var day_length_seconds: float = 1800.0
@export var start_hour: float = 17.5
@export var sun_light_path: NodePath = NodePath("../SunLight")
@export var world_env_path: NodePath = NodePath("../WorldEnvironment")

var current_hour: float = 17.5
var day_number: int = 1

## Normalized time of day (`0.0 .. 1.0`, where `0.25 = 06:00 Sunrise`, `0.50 = 12:00 Noon`, `0.75 = 18:00 Sunset`).
var time_of_day: float:
	get:
		return clampf(current_hour / 24.0, 0.0, 1.0)
	set(value):
		current_hour = fposmod(value * 24.0, 24.0)
		_apply_lighting(current_hour)

var _sun_light: DirectionalLight3D = null
var _last_applied_hour: float = -100.0
var _world_env: WorldEnvironment = null
var _sun_mesh: MeshInstance3D = null
var _moon_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("day_night_cycle")
	if not GameSession.active_world_data.is_empty():
		var dn_data: Dictionary = GameSession.active_world_data.get("day_night", {})
		if not dn_data.is_empty():
			current_hour = float(dn_data.get("hour", start_hour))
			day_number = int(dn_data.get("day", 1))
		else:
			current_hour = start_hour
	else:
		current_hour = start_hour

	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	_world_env = get_node_or_null(world_env_path) as WorldEnvironment
	_build_celestial_bodies()
	_apply_lighting(current_hour)


func _build_celestial_bodies() -> void:
	if _sun_light == null:
		return
	var sun_img: Image = TexturePack.load_image("res://assets/textures/environment/sun.png")
	if sun_img != null:
		var sun_mat := StandardMaterial3D.new()
		sun_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sun_mat.albedo_texture = ImageTexture.create_from_image(sun_img)
		sun_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sun_mesh = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(26.0, 26.0)
		_sun_mesh.mesh = q
		_sun_mesh.material_override = sun_mat
		_sun_mesh.position = Vector3(0.0, 0.0, -180.0)
		_sun_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sun_light.add_child(_sun_mesh)

	var moon_img: Image = TexturePack.load_image("res://assets/textures/environment/moon.png")
	if moon_img != null:
		var moon_mat := StandardMaterial3D.new()
		moon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		moon_mat.albedo_texture = ImageTexture.create_from_image(moon_img)
		moon_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_moon_mesh = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(24.0, 24.0)
		_moon_mesh.mesh = q
		_moon_mesh.material_override = moon_mat
		_moon_mesh.position = Vector3(0.0, 0.0, 180.0)
		_moon_mesh.rotation = Vector3(0.0, PI, 0.0)
		_moon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sun_light.add_child(_moon_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T:
			advance_hours(2.5)


func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var hours_per_sec: float = 24.0 / day_length_seconds
	advance_hours(hours_per_sec * delta, false)


func advance_hours(delta_hours: float, force_update: bool = true) -> void:
	current_hour += delta_hours
	while current_hour >= 24.0:
		current_hour -= 24.0
		day_number += 1
	# Sky, sun and fog only need refreshing about once a second of game time; changing the sky
	# material every frame forces the renderer to rebuild the sky each frame.
	if force_update or absf(current_hour - _last_applied_hour) >= 0.01:
		_apply_lighting(current_hour)


func is_night_time() -> bool:
	# Night is between 18:30 (dusk) and 06:00 (dawn)
	return current_hour >= 18.5 or current_hour < 6.0


func advance_to_morning() -> void:
	# Sleep advances time directly to 06:00 AM (Sunrise) the next morning
	if current_hour >= 6.0:
		day_number += 1
	current_hour = 6.0
	_apply_lighting(current_hour)


func get_formatted_time() -> String:
	var h: int = int(floor(current_hour)) % 24
	var m: int = int(floor((current_hour - floor(current_hour)) * 60.0)) % 60
	return "Day %d %02d:%02d" % [day_number, h, m]


func _apply_lighting(hour: float) -> void:
	_last_applied_hour = hour
	# Convert hour (0..24) into sun elevation angle:
	# 6:00 = sunrise (0 deg), 12:00 = zenith (90 deg), 18:00 = sunset (180 deg), 0:00 = nadir (270 deg)
	var sun_phase: float = ((hour - 6.0) / 24.0) * TAU
	var sun_height: float = sin(sun_phase) # -1.0 (midnight) to +1.0 (noon)
	_update_terrain_light_globals(sun_height)

	if _sun_light != null:
		var pitch_angle: float = -sun_phase
		_sun_light.rotation = Vector3(pitch_angle, deg_to_rad(-32.0), 0.0)

		if sun_height > 0.0:
			var day_factor: float = clampf(sun_height, 0.0, 1.0)
			_sun_light.light_energy = lerpf(0.55, 1.45, pow(day_factor, 0.6))
			var golden_hour_color := Color(1.0, 0.72, 0.38)
			var noon_color := Color(1.0, 0.98, 0.92)
			_sun_light.light_color = golden_hour_color.lerp(noon_color, clampf(sun_height * 2.4 - 0.2, 0.0, 1.0))
			_sun_light.light_volumetric_fog_energy = lerpf(2.6, 1.6, day_factor)
		else:
			# Moonlight at night
			_sun_light.rotation = Vector3(-(sun_phase + PI), deg_to_rad(-32.0), 0.0)
			_sun_light.light_energy = 0.22
			_sun_light.light_color = Color(0.55, 0.68, 0.95)
			_sun_light.light_volumetric_fog_energy = 1.0

	if _world_env != null and _world_env.environment != null:
		var env: Environment = _world_env.environment
		var daylight: float = clampf((sun_height + 0.18) / 1.18, 0.0, 1.0)
		var twilight: float = clampf(1.0 - absf(sun_height) * 3.5, 0.0, 1.0)

		var night_top := Color(0.04, 0.06, 0.14)
		var day_top := Color(0.32, 0.58, 0.92)
		var top_col: Color = night_top.lerp(day_top, daylight)

		var night_horizon := Color(0.08, 0.11, 0.22)
		var day_horizon := Color(0.68, 0.84, 0.96)
		var sunset_horizon := Color(0.95, 0.52, 0.32)
		var horizon_col: Color = night_horizon.lerp(day_horizon, daylight).lerp(sunset_horizon, twilight * 0.65)

		env.fog_light_color = horizon_col
		env.ambient_light_color = Color(0.18, 0.22, 0.34).lerp(Color(0.75, 0.80, 0.88), daylight)
		env.volumetric_fog_albedo = Color(0.12, 0.16, 0.30).lerp(Color(0.96, 0.88, 0.76), daylight).lerp(Color(1.0, 0.70, 0.45), twilight * 0.75)

		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
			sky_mat.sky_top_color = top_col
			sky_mat.sky_horizon_color = horizon_col
			sky_mat.ground_horizon_color = horizon_col


## Terrain is unshaded with baked light levels; the day/night cycle just tells the shaders how
## much to darken skylight (0 at noon, 11 levels at midnight) and what color it has.
func _update_terrain_light_globals(sun_height: float) -> void:
	var daylight: float = clampf((sun_height + 0.18) / 1.18, 0.0, 1.0)
	var darken: float = (1.0 - daylight) * 11.0
	var twilight: float = clampf(1.0 - absf(sun_height) * 3.5, 0.0, 1.0)
	var night_tint := Color(0.70, 0.76, 1.0)
	var day_tint := Color(1.0, 1.0, 1.0)
	var dusk_tint := Color(1.0, 0.86, 0.72)
	var tint: Color = night_tint.lerp(day_tint, daylight).lerp(dusk_tint, twilight * 0.35)
	RenderingServer.global_shader_parameter_set("vc_sky_darken", darken)
	RenderingServer.global_shader_parameter_set("vc_sky_tint", Vector3(tint.r, tint.g, tint.b))
