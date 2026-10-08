#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;
layout(push_constant) uniform PC {
    vec4 c0; vec4 c1; vec4 c2; vec4 c3;   // MVP columns (outline passes shift them in screen space)
    vec3 light;
    vec4 color;                            // flat highlight colour (alpha = opacity)
} pc;
layout(location = 0) out vec4 vColor;
invariant gl_Position; // identical depth to model.vert, so the fill pass can use depth LEQUAL
void main() {
    gl_Position = pc.c0 * inPos.x + pc.c1 * inPos.y + pc.c2 * inPos.z + pc.c3;
    vColor = pc.color;
}
