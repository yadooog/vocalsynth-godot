// Flowers: flat colour from each instance.
shader_type spatial;
render_mode unshaded;

void fragment() {
	ALBEDO = COLOR.rgb;
}
