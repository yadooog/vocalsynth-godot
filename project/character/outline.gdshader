// Ink outline: the mesh pushed out a little along its normals (in view space, so the
// line stays an even thickness even when the head is squashed or stretched), drawn
// inside-out in near-black behind the real mesh.
shader_type spatial;
render_mode unshaded, cull_front, skip_vertex_transform;

uniform float width = 0.035;

void vertex() {
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	VERTEX = v + n * width;
	NORMAL = n;
}

void fragment() {
	ALBEDO = vec3(0.07, 0.07, 0.07);
}
