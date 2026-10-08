#version 450
#include "../glsl/filters.glsl"
layout(set = 0, binding = 0) uniform sampler2D tex;
layout(push_constant) uniform PCF { layout(offset = 96) uint mode; } pcf; // interpolation mode, see filters.glsl
layout(location = 0) in vec4 vColor;
layout(location = 1) in vec2 vUV;
layout(location = 0) out vec4 outColor;
void main() { outColor = sampleFiltered(tex, vUV, pcf.mode) * vColor; }
