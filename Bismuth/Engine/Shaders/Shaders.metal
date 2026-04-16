#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// Texture flag bits (must match Swift-side constants)
constant uint TextureFlagBaseColor          = 1;
constant uint TextureFlagMetallicRoughness  = 2;
constant uint TextureFlagNormal             = 4;

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoords;
};

[[vertex]]
VertexOut vertex_main(VertexIn in [[stage_in]],
                      constant ViewConstants *views [[buffer(1)]],
                      constant InstanceConstants *instances [[buffer(2)]],
                      uint instanceID [[instance_id]])
{
    constant auto &view = views[0];
    constant auto &instance = instances[instanceID];

    VertexOut out;
    float4 worldPos = instance.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.worldNormal = instance.normalMatrix * in.normal;
    out.position = view.projectionMatrix * view.viewMatrix * worldPos;
    out.texCoords = in.texCoords;
    return out;
}

// GGX/Trowbridge-Reitz normal distribution function
static float distributionGGX(float NdotH, float roughness) {
    float a  = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * denom * denom);
}

// Schlick-GGX geometry function (single direction)
static float geometrySchlickGGX(float NdotX, float roughness) {
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    return NdotX / (NdotX * (1.0 - k) + k);
}

// Smith's method combining both view and light directions
static float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

// Schlick approximation for Fresnel reflectance
static float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// Schlick-Fresnel with roughness attenuation for IBL specular
static float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// Compute a cotangent-frame TBN matrix from screen-space derivatives.
// This allows normal mapping without requiring tangent vertex attributes.
static float3x3 cotangentFrame(float3 N, float3 p, float2 uv) {
    float3 dp1 = dfdx(p);
    float3 dp2 = dfdy(p);
    float2 duv1 = dfdx(uv);
    float2 duv2 = dfdy(uv);

    float3 dp2perp = cross(dp2, N);
    float3 dp1perp = cross(N, dp1);
    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    float invmax = rsqrt(max(dot(T, T), dot(B, B)));
    return float3x3(T * invmax, B * invmax, N);
}

[[fragment]]
float4 fragment_main(VertexOut in [[stage_in]],
                     constant SceneConstants &scene [[buffer(0)]],
                     constant MaterialConstants *materials [[buffer(1)]],
                     constant LightConstants *lights [[buffer(2)]],
                     texture2d<float> baseColorMap [[texture(0)]],
                     texture2d<float> metallicRoughnessMap [[texture(1)]],
                     texture2d<float> normalMap [[texture(2)]],
                     texturecube<float> diffuseIrradiance [[texture(3)]],
                     texturecube<float> specularIrradiance [[texture(4)]],
                     texture2d<float> brdfLUT [[texture(5)]],
                     sampler textureSampler [[sampler(0)]])
{
    constant auto &material = materials[0];
    uint flags = material.textureFlags;

    float3 N = normalize(in.worldNormal);
    float3 V = normalize(scene.cameraPosition.xyz - in.worldPosition);

    // Base color
    float4 baseColorSample = material.baseColorFactor;
    if (flags & TextureFlagBaseColor) {
        baseColorSample *= baseColorMap.sample(textureSampler, in.texCoords);
    }
    float3 baseColor = baseColorSample.rgb;

    // Metallic-roughness
    float roughness = material.roughnessFactor;
    float metalness = material.metalnessFactor;
    if (flags & TextureFlagMetallicRoughness) {
        float4 mrSample = metallicRoughnessMap.sample(textureSampler, in.texCoords);
        roughness *= mrSample.g; // Green channel = roughness
        metalness *= mrSample.b; // Blue channel = metallic
    }
    roughness = clamp(roughness, 0.04, 1.0);
    metalness = saturate(metalness);

    // Normal mapping
    if (flags & TextureFlagNormal) {
        float3x3 TBN = cotangentFrame(N, in.worldPosition, in.texCoords);
        float3 normalTS = normalMap.sample(textureSampler, in.texCoords).rgb * 2.0 - 1.0;
        normalTS.xy *= material.normalScale;
        N = normalize(TBN * normalTS);
    }

    // Dielectrics reflect ~4% at normal incidence; metals use their base color
    float3 F0 = mix(float3(0.04), baseColor, metalness);

    float NdotV = max(dot(N, V), 0.001);

    float3 Lo = float3(0.0);

    // Direct lighting (analytical lights)
    for (uint i = 0; i < scene.lightCount; i++) {
        constant auto &light = lights[i];
        float3 L = normalize(-light.direction);
        float3 H = normalize(V + L);
        float3 radiance = light.color;

        float NdotL = max(dot(N, L), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        float HdotV = max(dot(H, V), 0.0);

        // Cook-Torrance specular BRDF
        float  D = distributionGGX(NdotH, roughness);
        float  G = geometrySmith(NdotV, NdotL, roughness);
        float3 F = fresnelSchlick(HdotV, F0);

        float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);

        // Energy-conserving diffuse: metals have no diffuse component
        float3 kD = (1.0 - F) * (1.0 - metalness);
        float3 diffuse = kD * baseColor / M_PI_F;

        Lo += (diffuse + specular) * radiance * NdotL;
    }

    // Image-based lighting (split-sum approximation)
    float3 ambient;
    if (scene.environmentIntensity > 0.0) {
        constexpr sampler envSampler(coord::normalized, filter::linear, mip_filter::linear);

        float3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD = (1.0 - F) * (1.0 - metalness);

        // Diffuse IBL: sample irradiance cubemap with surface normal
        float3 irradiance = diffuseIrradiance.sample(envSampler, scene.environmentTransform * N).rgb;
        float3 diffuseIBL = kD * baseColor * irradiance;

        // Specular IBL: sample prefiltered environment at roughness-based mip level
        float3 R = reflect(-V, N);
        R = scene.environmentTransform * R;
        float mipCount = float(specularIrradiance.get_num_mip_levels());
        float lod = roughness * (mipCount - 1.0);
        float3 prefilteredColor = specularIrradiance.sample(envSampler, R, level(lod)).rgb;

        // BRDF integration lookup
        float2 envBRDF = brdfLUT.sample(envSampler, float2(NdotV, roughness)).rg;
        float3 specularIBL = prefilteredColor * (F * envBRDF.x + envBRDF.y);

        ambient = (diffuseIBL + specularIBL) * scene.environmentIntensity;
    } else {
        ambient = scene.ambientIntensity * baseColor;
    }

    float3 color = ambient + Lo;

    return float4(color, baseColorSample.a);
}
