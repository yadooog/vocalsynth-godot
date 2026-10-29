// Flat cel shading in three tones, lit from a fixed direction (the camera never moves).
shader_type spatial;
render_mode unshaded;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 light_dir_view = vec3(-0.35, 0.65, 0.65);

void fragment() {
	float ndl = dot(normalize(NORMAL), normalize(light_dir_view));
	float tone = ndl > 0.55 ? 1.0 : (ndl > 0.05 ? 0.86 : 0.7);
	ALBEDO = albedo.rgb * tone;
}
