// Texture interpolation filters, included by ui.frag / model.frag / model_dither.frag (#include is resolved by shader.luau).
// mode: 0 = Linear and 1 = Nearest Neighbor (the bound sampler does the work), 2 = Cubic (Catmull-Rom), 3 = Cubic B-spline,
//       4 = Mitchell-Netravali, 5 = Lanczos-3.  Modes 2..5 read texels directly (texelFetch, clamp-to-edge) and weight them here.

float cubicWeight(float x, float B, float C) {
    x = abs(x);
    if (x < 1.0)
        return ((12.0 - 9.0 * B - 6.0 * C) * x * x * x + (-18.0 + 12.0 * B + 6.0 * C) * x * x + (6.0 - 2.0 * B)) / 6.0;
    if (x < 2.0)
        return ((-B - 6.0 * C) * x * x * x + (6.0 * B + 30.0 * C) * x * x + (-12.0 * B - 48.0 * C) * x + (8.0 * B + 24.0 * C)) / 6.0;
    return 0.0;
}

float lanczos3Weight(float x) {
    x = abs(x);
    if (x < 1e-5) return 1.0;
    if (x >= 3.0) return 0.0;
    float px = 3.14159265 * x;
    return 3.0 * sin(px) * sin(px / 3.0) / (px * px);
}

float filterWeight(float x, uint mode) {
    if (mode == 2u) return cubicWeight(x, 0.0, 0.5);
    if (mode == 3u) return cubicWeight(x, 1.0, 0.0);
    if (mode == 4u) return cubicWeight(x, 1.0 / 3.0, 1.0 / 3.0);
    return lanczos3Weight(x);
}

vec4 sampleFiltered(sampler2D tex, vec2 uv, uint mode) {
    if (mode < 2u) return texture(tex, uv);
    ivec2 size = textureSize(tex, 0);
    vec2 p = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(p));
    vec2 f = p - vec2(base);
    int reach = (mode == 5u) ? 3 : 2;           // taps base+1-reach .. base+reach on each axis (4 for cubic, 6 for Lanczos)
    vec4 sum = vec4(0.0);                        // premultiplied, so transparent texels do not bleed their colour
    float wsum = 0.0;
    for (int j = 1 - reach; j <= reach; j++) {
        float wy = filterWeight(float(j) - f.y, mode);
        for (int i = 1 - reach; i <= reach; i++) {
            float w = filterWeight(float(i) - f.x, mode) * wy;
            vec4 c = texelFetch(tex, clamp(base + ivec2(i, j), ivec2(0), size - 1), 0);
            sum += w * vec4(c.rgb * c.a, c.a);
            wsum += w;
        }
    }
    sum /= wsum;
    float a = clamp(sum.a, 0.0, 1.0);
    return vec4(clamp(sum.rgb / max(sum.a, 1e-5), 0.0, 1.0), a);
}
