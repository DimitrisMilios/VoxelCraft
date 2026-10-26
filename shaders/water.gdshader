shader_type spatial;
render_mode depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.24, 0.74, 0.82, 0.40);
uniform vec4 deep_color : source_color = vec4(0.04, 0.30, 0.56, 0.90);
uniform float depth_distance : hint_range(0.5, 20.0) = 5.5;
uniform float beer_factor : hint_range(0.1, 5.0) = 1.25;

uniform sampler2D wave_normal_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 wave_speed_1 = vec2(0.022, 0.014);
uniform vec2 wave_speed_2 = vec2(-0.016, 0.024);
uniform float wave_scale_1 = 0.18;
uniform float wave_scale_2 = 0.32;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float specular : hint_range(0.0, 1.0) = 0.95;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

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

	// Linear depth reconstruction
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;
	float water_depth = max(0.0, linear_depth - (-VERTEX.z));

	float depth_factor = clamp(water_depth / depth_distance, 0.0, 1.0);
	depth_factor = pow(depth_factor, beer_factor);

	// Refraction of underwater terrain
	vec2 refr_offset = wave_perturb * refraction_strength * (1.0 - depth_factor * 0.5);
	float refr_depth_raw = texture(depth_texture, SCREEN_UV + refr_offset).r;
	vec3 refr_ndc = vec3((SCREEN_UV + refr_offset) * 2.0 - 1.0, refr_depth_raw);
	vec4 refr_view = INV_PROJECTION_MATRIX * vec4(refr_ndc, 1.0);
	refr_view.xyz /= refr_view.w;
	if (-refr_view.z < -VERTEX.z) {
		refr_offset = vec2(0.0);
	}
	vec3 refracted_screen = texture(screen_texture, SCREEN_UV + refr_offset).rgb;

	// Fresnel reflection for glancing sun / sky highlights
	float fresnel = clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0);
	fresnel = pow(fresnel, 4.0);

	vec4 water_col = mix(shallow_color, deep_color, depth_factor);

	ALBEDO = mix(refracted_screen, water_col.rgb, water_col.a * (1.0 - fresnel * 0.4));
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	ALPHA = 1.0;
}
