class_name DayNightCycle
extends Node
## Controls dynamic Day/Night cycle, rotating SunLight and blending sky/ambient/fog colors.
## Press [T] to fast-forward time by +2.5 hours.

@export var day_length_seconds: float = 360.0
@export var start_hour: float = 9.5
@export var sun_light_path: NodePath = NodePath("../SunLight")
@export var world_env_path: NodePath = NodePath("../WorldEnvironment")

var current_hour: float = 9.5
var day_number: int = 1

var _sun_light: DirectionalLight3D = null
var _world_env: WorldEnvironment = null


func _ready() -> void:
	add_to_group("day_night_cycle")
	current_hour = start_hour
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	_world_env = get_node_or_null(world_env_path) as WorldEnvironment
	_apply_lighting(current_hour)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T:
			advance_hours(2.5)


func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	var hours_per_sec: float = 24.0 / day_length_seconds
	advance_hours(hours_per_sec * delta)


func advance_hours(delta_hours: float) -> void:
	current_hour += delta_hours
	while current_hour >= 24.0:
		current_hour -= 24.0
		day_number += 1
	_apply_lighting(current_hour)


func get_formatted_time() -> String:
	var h: int = int(floor(current_hour)) % 24
	var m: int = int(floor((current_hour - floor(current_hour)) * 60.0)) % 60
	return "Day %d %02d:%02d" % [day_number, h, m]


func _apply_lighting(hour: float) -> void:
	# Convert hour (0..24) into sun elevation angle:
	# 6:00 = sunrise (0 deg), 12:00 = zenith (90 deg), 18:00 = sunset (180 deg), 0:00 = nadir (270 deg)
	var sun_phase: float = ((hour - 6.0) / 24.0) * TAU
	var sun_height: float = sin(sun_phase) # -1.0 (midnight) to +1.0 (noon)

	if _sun_light != null:
		var pitch_angle: float = -sun_phase
		_sun_light.rotation = Vector3(pitch_angle, deg_to_rad(-32.0), 0.0)

		if sun_height > 0.0:
			var day_factor: float = clampf(sun_height, 0.0, 1.0)
			_sun_light.light_energy = lerpf(0.25, 1.15, pow(day_factor, 0.6))
			var sunset_color := Color(1.0, 0.62, 0.36)
			var noon_color := Color(1.0, 0.98, 0.94)
			_sun_light.light_color = sunset_color.lerp(noon_color, clampf(sun_height * 2.2, 0.0, 1.0))
		else:
			# Moonlight at night
			_sun_light.rotation = Vector3(-(sun_phase + PI), deg_to_rad(-32.0), 0.0)
			_sun_light.light_energy = 0.18
			_sun_light.light_color = Color(0.55, 0.68, 0.95)

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

		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
			sky_mat.sky_top_color = top_col
			sky_mat.sky_horizon_color = horizon_col
			sky_mat.ground_horizon_color = horizon_col
