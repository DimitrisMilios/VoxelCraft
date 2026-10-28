shader_type spatial;
// Unshaded translucent water. Light comes from the baked per-vertex sky/block light (UV2), the same
// as terrain, so water in caves and at night darkens correctly without any per-pixel lighting cost.
render_mode unshaded, depth_draw_always, cull_back, blend_mix;

uniform vec4 water_color : source_color = vec4(0.14, 0.54, 0.84, 0.68);
uniform vec4 deep_color : source_color = vec4(0.04, 0.24, 0.52, 0.85);

uniform sampler2D wave_normal_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 wave_speed_1 = vec2(0.022, 0.014);
uniform vec2 wave_speed_2 = vec2(-0.016, 0.024);
uniform float wave_scale_1 = 0.20;
uniform float wave_scale_2 = 0.35;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.80;

global uniform float vc_sky_darken;
global uniform vec3 vc_sky_tint;
global uniform vec3 vc_block_tint;

varying vec3 v_world_pos;
varying vec2 v_light;
varying float v_shade;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_light = UV2;
	v_shade = COLOR.r;
}

float light_curve(float level) {
	float f = 1.0 - clamp(level, 0.0, 15.0) / 15.0;
	float b = (1.0 - f) / (f * 3.0 + 1.0) * 0.95 + 0.05;
	float lifted = 1.0 - pow(1.0 - b, 4.0);
	return mix(b, lifted, 0.45);
}

void fragment() {
	vec2 world_uv = v_world_pos.xz;
	vec2 uv1 = world_uv * wave_scale_1 + TIME * wave_speed_1;
	vec2 uv2 = world_uv * wave_scale_2 + TIME * wave_speed_2;

	vec3 n1 = texture(wave_normal_1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal_2, uv2).rgb * 2.0 - 1.0;
	vec2 wave_perturb = (n1.xy + n2.xy) * 0.5;

	vec3 wave_view = (VIEW_MATRIX * vec4(wave_perturb.x, 0.0, wave_perturb.y, 0.0)).xyz;
	vec3 n = normalize(NORMAL + wave_view * normal_strength);

	float fresnel = clamp(1.0 - dot(n, VIEW), 0.0, 1.0);
	float fresnel_pow = pow(fresnel, 3.2);

	float sky = max(v_light.x * 15.0 - vc_sky_darken, 0.0);
	float blk = v_light.y * 15.0;
	vec3 light = max(vc_sky_tint * light_curve(sky), vc_block_tint * light_curve(blk));

	vec3 base_col = mix(water_color.rgb, deep_color.rgb, 0.35);
	vec3 sky_reflection = vec3(0.68, 0.86, 1.0) * vc_sky_tint * light_curve(sky);

	ALBEDO = mix(base_col * light, sky_reflection, fresnel_pow * 0.65) * v_shade;
	ALPHA = clamp(water_color.a + fresnel_pow * 0.25, 0.0, 0.95);
}
