// Unshaded voxel terrain: all lighting is baked per vertex (smooth sky/block light + AO),
// so the GPU does one texture fetch and a handful of ALU ops per pixel. No dynamic lights,
// no shadows, no normal maps — this is what keeps low-end integrated GPUs at 60 FPS.

// Every block face is a layer of this array so each tile gets clean mipmaps without bleeding.
uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_enable;

// Shared with the water shader and updated by DayNightCycle.
global uniform float vc_sky_darken;
global uniform vec3 vc_sky_tint;
global uniform vec3 vc_block_tint;

varying vec3 v_tint;
varying vec2 v_light;
varying float v_layer;

void vertex() {
	v_tint = COLOR.rgb;
	v_layer = floor(COLOR.a * 255.0 + 0.5);
	v_light = UV2;
}

// Classic light-level -> brightness curve (level 0..15 in, 0.05..1.0 out), with a mild gamma lift.
float light_curve(float level) {
	float f = 1.0 - clamp(level, 0.0, 15.0) / 15.0;
	float b = (1.0 - f) / (f * 3.0 + 1.0) * 0.95 + 0.05;
	float lifted = 1.0 - pow(1.0 - b, 4.0);
	return mix(b, lifted, 0.45);
}

void fragment() {
	vec4 tex = texture(atlas, vec3(UV, v_layer));
#ifdef CUTOUT
	if (tex.a < 0.5) {
		discard;
	}
#endif
	float sky = max(v_light.x * 15.0 - vc_sky_darken, 0.0);
	float blk = v_light.y * 15.0;
	vec3 light = max(vc_sky_tint * light_curve(sky), vc_block_tint * light_curve(blk));
	ALBEDO = tex.rgb * v_tint * light;
}
