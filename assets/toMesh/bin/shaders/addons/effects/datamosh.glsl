// Datamosh-style smear: blocks keep (and drag) their previous picture until the new picture differs a lot,
// or a block randomly refreshes. Uses previous(), so it costs one extra window-sized image per element.
#pragma setting float blockSize 16      // block edge in pixels
#pragma setting float threshold 0.35    // how different a block must be to be refreshed
#pragma setting float smear 1.0         // how far (in blocks) the old picture is dragged along detected motion
#pragma setting float refresh 0.01      // chance per block and frame to refresh anyway
#pragma setting float amount 1.0        // 0 = off, 1 = full effect

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + float(frame) * 0.37) * 43758.5453); }
float lum(vec4 c) { return dot(c, vec4(0.299, 0.587, 0.114, 0.5)); }

vec4 effect(vec2 uv) {
	vec4 cur = source(uv);
	vec2 block = floor(uv * resolution / blockSize);
	vec2 centre = (block + 0.5) * blockSize * pixelSize;
	vec2 stp = blockSize * pixelSize;

	// crude motion: where did the picture get brighter around the block centre
	vec2 motion = vec2(
		lum(source(centre + vec2(stp.x, 0.0))) - lum(source(centre - vec2(stp.x, 0.0))),
		lum(source(centre + vec2(0.0, stp.y))) - lum(source(centre - vec2(0.0, stp.y)))
	);
	vec4 old = previous(uv - motion * smear * stp);
	float change = length(source(centre) - previous(centre));
	float snap = max(step(threshold, change), step(1.0 - refresh, hash(block)));
	vec4 moshed = mix(old, cur, snap);
	return mix(cur, moshed, amount);
}
