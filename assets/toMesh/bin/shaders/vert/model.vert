#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(push_constant) uniform PC {
    vec4 c0; vec4 c1; vec4 c2; vec4 c3;   // MVP columns
    vec3 light;                            // light direction in object space
    vec4 color;
} pc;
layout(location = 0) out vec4 vColor;
layout(location = 1) out vec2 vUV;
invariant gl_Position; // same result as highlight.vert (the highlight fill pass depends on equal depth)
void main() {
    gl_Position = pc.c0 * inPos.x + pc.c1 * inPos.y + pc.c2 * inPos.z + pc.c3;
    float intensity = 0.65 + 0.35 * dot(inNormal, pc.light);
    vColor = vec4(pc.color.rgb * intensity, pc.color.a);
    vUV = inUV;
}
