shader_type spatial;
render_mode depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.14, 0.54, 0.84, 0.68);
uniform vec4 deep_color : source_color = vec4(0.04, 0.24, 0.52, 0.85);

uniform sampler2D wave_normal_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 wave_speed_1 = vec2(0.022, 0.014);
uniform vec2 wave_speed_2 = vec2(-0.016, 0.024);
uniform float wave_scale_1 = 0.20;
uniform float wave_scale_2 = 0.35;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.80;

uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float metallic : hint_range(0.0, 1.0) = 0.06;
uniform float specular : hint_range(0.0, 1.0) = 0.94;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_uv = v_world_pos.xz;
	vec2 uv1 = world_uv * wave_scale_1 + TIME * wave_speed_1;
	vec2 uv2 = world_uv * wave_scale_2 + TIME * wave_speed_2;

	vec3 n1 = texture(wave_normal_1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal_2, uv2).rgb * 2.0 - 1.0;
	vec2 wave_perturb = (n1.xy + n2.xy) * 0.5;

	// View-space wave normal perturbation applied to surface normal
	vec3 wave_view = (VIEW_MATRIX * vec4(wave_perturb.x, 0.0, wave_perturb.y, 0.0)).xyz;
	NORMAL = normalize(NORMAL + wave_view * normal_strength);

	// Fresnel reflection: glancing angles reflect light sky blue, top-down is crystal clear
	float fresnel = clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel_pow = pow(fresnel, 3.2);

	vec3 base_col = mix(water_color.rgb, deep_color.rgb, 0.35);
	vec3 sky_reflection = vec3(0.68, 0.86, 1.0);

	ALBEDO = mix(base_col, sky_reflection, fresnel_pow * 0.65);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	ALPHA = clamp(water_color.a + fresnel_pow * 0.25, 0.0, 0.95);
}
