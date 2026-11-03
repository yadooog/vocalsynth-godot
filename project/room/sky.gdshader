// The sky: a big dome, soft blue overhead fading to the haze at the horizon.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 horizon = vec3(0.925, 0.937, 0.925);
	vec3 top = vec3(0.745, 0.855, 0.925);
	ALBEDO = mix(horizon, top, smoothstep(0.0, 0.55, dir.y));
}
