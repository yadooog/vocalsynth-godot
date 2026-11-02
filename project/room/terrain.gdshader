// The hills: flat cel shading like the rest of the world, coloured per vertex.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 light_dir_view = vec3(-0.35, 0.65, 0.65);

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL; // both sides lit the same
	float ndl = dot(normalize(n), normalize(light_dir_view));
	float tone = ndl > 0.55 ? 1.0 : (ndl > 0.05 ? 0.9 : 0.78);
	ALBEDO = COLOR.rgb * tone;
}
