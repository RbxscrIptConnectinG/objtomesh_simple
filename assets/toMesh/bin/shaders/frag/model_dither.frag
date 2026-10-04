#version 450
layout(set = 0, binding = 0) uniform sampler2D tex;
layout(location = 0) in vec4 vColor;
layout(location = 1) in vec2 vUV;
layout(location = 0) out vec4 outColor;
void main() {
    vec4 c = texture(tex, vUV) * vColor;
    uint x = uint(gl_FragCoord.x), y = uint(gl_FragCoord.y);
    uint xy = x ^ y;
    uint bayer = ((xy & 1u) << 3) + ((y & 1u) << 2) + (((xy >> 1) & 1u) << 1) + ((y >> 1) & 1u);
    if (c.a <= (float(bayer) + 0.5) / 16.0) discard;
    outColor = vec4(c.rgb, 1.0);
}
