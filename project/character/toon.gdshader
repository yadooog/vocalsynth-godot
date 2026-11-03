// Flat cel shading in three tones, lit from a fixed direction (the camera never moves).
// Far away things fade into the haze at the horizon. `planks` draws floorboards on tops.
shader_type spatial;
render_mode unshaded;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 light_dir_view = vec3(-0.35, 0.65, 0.65);
uniform float planks = 0.0;
const vec3 HAZE = vec3(0.925, 0.937, 0.925);
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	float ndl = dot(normalize(NORMAL), normalize(light_dir_view));
	float tone = ndl > 0.55 ? 1.0 : (ndl > 0.05 ? 0.86 : 0.7);
	vec3 col = albedo.rgb * tone;
	if (planks > 0.0 && world_normal.y > 0.7) {
		float board = floor(world_pos.x / 0.9);
		float edge = fract(world_pos.x / 0.9);
		col *= 0.95 + 0.07 * hash(board);
		col *= (edge < 0.035 || edge > 0.965) ? 0.82 : 1.0;
	}
	ALBEDO = mix(col, HAZE, smoothstep(70.0, 230.0, length(VERTEX)) * 0.7);
}
