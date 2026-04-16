#if __METAL__
#include <metal_stdlib>
using namespace metal;
using simd_float4x4 = float4x4;
using simd_float3x3 = float3x3;
#else
#include <simd/simd.h>
#endif

struct InstanceConstants {
    simd_float4x4 modelMatrix;
    simd_float3x3 normalMatrix;
};

struct ViewConstants {
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
};

struct SceneConstants {
    simd_float3x3 environmentTransform;
    simd_float4 cameraPosition;
    simd_float3 ambientIntensity;
    uint32_t lightCount;
    float environmentIntensity;
    float backgroundLOD;
};

struct MaterialConstants {
    simd_float4 baseColorFactor;
    float roughnessFactor;
    float metalnessFactor;
    float normalScale;
    uint32_t textureFlags; // bit 0: baseColor, bit 1: metallicRoughness, bit 2: normal
};

struct LightConstants {
    simd_float3 position;
    simd_float3 direction;
    simd_float3 color;
};

struct SpecularPrefilteringParams{
    uint32_t /*BRDF*/ distribution;
    uint32_t sampleCount;
    float roughness;
    float lodBias;
    float cubemapSize;
};

struct DiffusePrefilteringParams {
    uint32_t /*BRDF*/ distribution;
    uint32_t sampleCount;
    float roughness;
    float lodBias;
    float cubemapSize;
};
