#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct SkyboxVertexOut {
    float4 position [[position]];
    float3 texCoords;
};

[[vertex]]
SkyboxVertexOut skybox_vertex(device float3 const *vertices [[buffer(0)]],
                              constant ViewConstants &view [[buffer(1)]],
                              constant SceneConstants &scene [[buffer(2)]],
                              uint vertexID [[vertex_id]])
{
    float3 position = vertices[vertexID];
    SkyboxVertexOut out;
    out.texCoords = position;
    float3x3 viewMatrix {
        view.viewMatrix[0].xyz,
        view.viewMatrix[1].xyz,
        view.viewMatrix[2].xyz
    };

    float4 clipPos = view.projectionMatrix * float4(viewMatrix * scene.environmentTransform * position, 1.0);
    out.position = float4(clipPos.xy, 0.0, clipPos.w);
    return out;
}

static float2 sample_equirectangular(float3 dir) {
    // Cartesian to polar
    float phi = atan2(dir.z, dir.x);
    float theta = acos(dir.y);

    // Polar to texture space
    float u = phi / (2.0 * M_PI_F) + 0.5;
    float v = theta / M_PI_F;

    return float2(u, v);
}

[[fragment]]
half4 skybox_fragment(SkyboxVertexOut in [[stage_in]],
                      constant SceneConstants &scene [[buffer(0)]],
                      texture2d<float> environmentTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, mip_filter::linear);

    float3 dir = normalize(in.texCoords);

    float2 uv = sample_equirectangular(dir);
    float3 color = environmentTexture.sample(textureSampler, uv, level(scene.backgroundLOD)).rgb;

    return half4(half3(color), 1.0);
}
