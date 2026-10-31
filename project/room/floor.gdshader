// The room's floor: white paper with a faint checker, two units a square.
shader_type spatial;
render_mode unshaded;

uniform vec4 light : source_color = vec4(0.965, 0.945, 0.918, 1.0);
uniform vec4 dark : source_color = vec4(0.925, 0.894, 0.855, 1.0);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / 2.0);
	ALBEDO = mod(cell.x + cell.y, 2.0) < 0.5 ? dark.rgb : light.rgb;
}
