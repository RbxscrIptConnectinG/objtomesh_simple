// Material shading shared by model.frag and model_dither.frag (included; #include is resolved by shader.luau).
//
// Without any material map or value (flags & 47 == 0) the result is the old look: the vertex shader's lighting (vColor) times the base texture.
// With a normal / roughness / metalness / ambient-occlusion map the fragment is lit here: one directional light, GGX specular,
// Schlick fresnel, a constant ambient term (there is no environment map). The maps are sampled with plain linear filtering and use the
// red channel (roughness / metalness / occlusion); the normal map is tangent space. Tangents come from screen-space derivatives,
// so the mesh needs only positions, normals and UVs.
#include "filters.glsl"

layout(set = 0, binding = 0) uniform sampler2D tex;          // base colour
layout(set = 1, binding = 0) uniform sampler2D normalTex;
layout(set = 2, binding = 0) uniform sampler2D roughnessTex;
layout(set = 3, binding = 0) uniform sampler2D metalnessTex;
layout(set = 4, binding = 0) uniform sampler2D occlusionTex;

layout(push_constant) uniform PCF {
    layout(offset = 96) uint mode;     // interpolation mode of the base texture, see filters.glsl
    uint flags;                        // 1 normal map, 2 roughness map, 4 metalness map, 8 occlusion map, 16 invert the normal map's green channel, 32 lit by this shader (roughness / metalness values without maps)
    float camX; float camY; float camZ; // camera position in object space
    float roughness;                   // multiplies the roughness map, or the roughness itself without a map
    float metalness;                   // same for metalness
    float occlusionStrength;           // 0 = ignore the occlusion map, 1 = full
} pcf;

layout(location = 0) in vec4 vColor;    // tint * simple vertex lighting (old look)
layout(location = 1) in vec2 vUV;
layout(location = 2) in vec3 vPos;      // object space
layout(location = 3) in vec3 vNormal;
layout(location = 4) in vec4 vTint;     // tint without lighting
layout(location = 5) in vec3 vLight;    // direction towards the light, object space

const float PI = 3.14159265;

vec4 shade() {
    vec4 base = sampleFiltered(tex, vUV, pcf.mode);
    if ((pcf.flags & 47u) == 0u) return base * vColor;

    vec4 albedo = base * vTint;
    vec3 N = normalize(vNormal);
    if (!gl_FrontFacing) N = -N;

    if ((pcf.flags & 1u) != 0u) {
        // cotangent frame from derivatives (negated: Vulkan's dFdy points down the framebuffer)
        vec3 dp1 = dFdx(vPos), dp2 = dFdy(vPos);
        vec2 duv1 = dFdx(vUV), duv2 = dFdy(vUV);
        vec3 dp2perp = cross(dp2, N), dp1perp = cross(N, dp1);
        vec3 T = -(dp2perp * duv1.x + dp1perp * duv2.x);
        vec3 B = -(dp2perp * duv1.y + dp1perp * duv2.y);
        float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
        vec3 m = texture(normalTex, vUV).xyz * 2.0 - 1.0;
        if ((pcf.flags & 16u) != 0u) m.y = -m.y;
        N = normalize(mat3(T * invmax, B * invmax, N) * m);
    }

    float rough = pcf.roughness;
    if ((pcf.flags & 2u) != 0u) rough *= texture(roughnessTex, vUV).r;
    rough = clamp(rough, 0.045, 1.0);
    float metal = pcf.metalness;
    if ((pcf.flags & 4u) != 0u) metal *= texture(metalnessTex, vUV).r;
    metal = clamp(metal, 0.0, 1.0);
    float ao = 1.0;
    if ((pcf.flags & 8u) != 0u) ao = mix(1.0, texture(occlusionTex, vUV).r, clamp(pcf.occlusionStrength, 0.0, 1.0));

    vec3 V = normalize(vec3(pcf.camX, pcf.camY, pcf.camZ) - vPos);
    vec3 L = normalize(vLight);
    vec3 H = normalize(L + V);
    float ndl = max(dot(N, L), 0.0);
    float ndv = max(dot(N, V), 1e-4);
    float ndh = max(dot(N, H), 0.0);
    float vdh = max(dot(V, H), 0.0);

    float a2 = pow(rough, 4.0);
    float dd = ndh * ndh * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * dd * dd);
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float G = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
    vec3 F0 = mix(vec3(0.04), albedo.rgb, metal);
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - vdh, 5.0);
    vec3 spec = min(D * G * F * PI / (4.0 * ndv), vec3(8.0));
    vec3 diffuse = albedo.rgb * (1.0 - metal) * ndl;
    vec3 ambient = (albedo.rgb * (1.0 - metal) * 0.3 + F0 * 0.12) * ao;

    return vec4(ambient + 0.85 * (diffuse * ao + spec * ndl), albedo.a);
}
