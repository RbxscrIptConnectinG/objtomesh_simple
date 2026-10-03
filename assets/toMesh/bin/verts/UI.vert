#version 450
layout(location = 0) in vec2 inPos;     // pixels
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;   // R8G8B8A8_UNORM
layout(push_constant) uniform PC { vec2 scale; } pc; // scale = 2 / framebufferSize
layout(location = 0) out vec2 vUV;
layout(location = 1) out vec4 vColor;
void main() {
    gl_Position = vec4(inPos * pc.scale - 1.0, 0.0, 1.0);
    vUV = inUV;
    vColor = inColor;
}
