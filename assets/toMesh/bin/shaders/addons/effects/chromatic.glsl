// Chromatic aberration: red and blue are shifted apart.
#pragma setting float offset 2.0        // pixels
vec4 effect(vec2 uv) {
	vec2 d = vec2(offset, 0.0) * pixelSize;
	vec4 c = source(uv);
	return vec4(source(uv + d).r, c.g, source(uv - d).b, max(c.a, max(source(uv + d).a, source(uv - d).a)));
}
