#include <metal_stdlib>
using namespace metal;

struct ShineUniforms {
    float2 size;
    float2 tilt;
    float angle;
    float intensity;
    float pulse;
    uint style;
    float4 lighting; // travel, angular response, reserved, reserved
    float4 backgroundMaterial; // roughness, reflection strength, grain, iridescence
    float4 balanceMaterial;
    float4 balanceColor;
    uint4 finishes; // background, balance, original white balance, reserved
};

struct ShineVertex {
    float4 position [[position]];
    float2 uv;
    float opacity;
};

vertex ShineVertex cardShineVertex(uint vertexID [[vertex_id]]) {
    const float2 points[] = { float2(0, 0), float2(2, 0), float2(0, 2) };
    float2 uv = points[vertexID];
    return { float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1), uv, 1 };
}

// Raw values match HomeCardShineSettings.Finish.
enum MaterialFinish : uint { finishNone, finishMatte, finishSatin, finishMetal, finishFoil };

struct CardLight {
    float field;
    float2 local;
};

CardLight cardLight(float2 uv, constant ShineUniforms &u, texture2d<float> light) {
    constexpr sampler sampleTexture(coord::normalized, address::clamp_to_edge, filter::linear);
    // UVs use the entire card: origin top-left, +x right, +y down. Translate before
    // inverse rotation. Compute this once, never relative to the balance's bounds.
    float2 point = (uv - 0.5) * u.size;
    float angle = u.angle;
    if (u.style == 0) {
        point -= u.tilt * u.size * float2(0.5, 0.3);
    } else if (u.style == 2) {
        point -= u.tilt * u.size * float2(0.42, 0.34) * u.lighting.x;
        angle *= 0.3;
    }
    float c = cos(angle), s = sin(angle);
    float2 local = float2(c * point.x + s * point.y, -s * point.x + c * point.y) / u.size.x;
    if (u.style == 2) {
        float2 ellipse = local / float2(0.52, 0.40);
        return { exp2(-dot(ellipse, ellipse) * 2.5), local };
    }
    // None uses the earlier band/radial coordinates and cached texture unchanged.
    float2 sampleUV = u.style == 1 ? local / 1.5 + 0.5 : float2(local.x / 1.8 + 0.5, 0.5);
    return { light.sample(sampleTexture, sampleUV).a, local };
}

float3 applyMaterial(float3 base, CardLight light, float4 material, uint finish,
                     constant ShineUniforms &u, float2 grain, float3 foilColor) {
    if (u.intensity == 0) { return base; }
    if (finish == finishNone) {
        // Original CSS plus-lighter, without material or angle attenuation.
        return min(base + light.field * u.intensity * material.y, 1.0);
    }
    float texture = mix(grain.x, grain.y, finish == finishSatin ? 0.7 : 0.15) - 0.5;
    float3 color = base * (1 + texture * material.z * 0.035);
    if (finish == finishMatte) { return saturate(color); }

    // Roughness changes only falloff, so all finishes retain the same light peaks.
    // No secondary reflection with its own center or opposing tilt transform.
    float reflection = pow(saturate(light.field), mix(2.6, 0.6, material.x));
    float incidence = mix(1.0, 0.85 + 0.15 * saturate(length(u.tilt)), u.lighting.y);
    float shine = reflection * u.intensity * material.y * incidence;
    float metallic = finish == finishMetal ? 1.0 : (finish == finishFoil ? 0.5 : 0.0);
    color *= 1 - metallic * u.intensity * material.y * 0.5 * (1 - reflection);
    color *= 1 + texture * material.z * shine * 0.3;
    float3 tint = mix(float3(1), foilColor, material.w);
    color += shine * tint * mix(1.15, 1.5, metallic);
    return saturate(color);
}

fragment float4 cardShineFragment(ShineVertex in [[stage_in]],
                                  constant ShineUniforms &u [[buffer(0)]],
                                  texture2d<float> background [[texture(0)]],
                                  texture2d<float> light [[texture(1)]],
                                  texture2d<float> balanceMask [[texture(2)]],
                                  texture2d<float> grainTexture [[texture(3)]],
                                  texture2d<float> colorRamp [[texture(4)]]) {
    constexpr sampler sampleTexture(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler repeatTexture(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    float3 color = background.sample(sampleTexture, in.uv).rgb;
    float mask = balanceMask.sample(sampleTexture, in.uv).a;
    CardLight illumination = cardLight(in.uv, u, light);
    float2 grain = float2(0.5);
    float3 foilColor = float3(1);
    if (u.backgroundMaterial.z > 0 || u.balanceMaterial.z > 0) {
        grain = grainTexture.sample(repeatTexture, in.uv * u.size / 64).rg;
    }
    if (u.backgroundMaterial.w > 0 || u.balanceMaterial.w > 0) {
        // Color follows the same light-local coordinates, without a separate tilt offset.
        float phase = 0.5 + dot(illumination.local, float2(0.45, 0.25));
        foilColor = colorRamp.sample(repeatTexture, float2(phase, 0.5)).rgb;
    }
    color = applyMaterial(color, illumination, u.backgroundMaterial, u.finishes.x, u, grain, foilColor);
    float3 balance = u.balanceColor.rgb;
    if (mask > 0) {
        balance = applyMaterial(balance, illumination, u.balanceMaterial, u.finishes.y, u, grain, foilColor);
        if (u.finishes.z != 0) {
            // The default Home Card uses white ink with opacity, not gray pigment.
            // Preserve the mask's 100% integer / 75% secondary alpha and express
            // material attenuation through transparency over the lit background.
            mask *= dot(balance, float3(0.2126, 0.7152, 0.0722));
            balance = float3(1);
        }
    }
    return float4(mix(color, balance, mask), 1);
}

// Stable sample sparkles for testing the reference's light-driven opacity and pulse settings.
constant float4 shineSymbols[] = {
    {0.10, 0.14, 9, 0.26}, {0.20, 0.09, 5, 0.12}, {0.46, 0.07, 5, 0.12},
    {0.78, 0.08, 8, 0.24}, {0.89, 0.13, 16, 0.48}, {0.95, 0.24, 7, 0.20},
    {0.06, 0.48, 5, 0.12}, {0.11, 0.76, 15, 0.44}, {0.07, 0.88, 8, 0.22},
    {0.21, 0.86, 6, 0.16}, {0.92, 0.62, 12, 0.36}, {0.86, 0.74, 6, 0.16},
    {0.93, 0.88, 11, 0.34}, {0.78, 0.91, 7, 0.18}
};

vertex ShineVertex cardShineSymbolVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                         constant ShineUniforms &u [[buffer(0)]]) {
    const float2 corners[] = { {0, 0}, {1, 0}, {0, 1}, {1, 0}, {1, 1}, {0, 1} };
    float4 symbol = shineSymbols[instance];
    float azimuth = atan2(symbol.x - 0.5, -(symbol.y - 0.5));
    float light = (abs(cos(u.angle + M_PI_F * 0.3 - azimuth)) + 1) * 0.5;
    float scale = 1 - u.pulse * (1 - light);
    float2 uv = corners[vertexID];
    float2 position = symbol.xy + (uv - 0.5) * symbol.z * scale / u.size;
    return { float4(position.x * 2 - 1, 1 - position.y * 2, 0, 1), uv, symbol.w * light };
}

fragment float4 cardShineSymbolFragment(ShineVertex in [[stage_in]], texture2d<float> symbol [[texture(0)]]) {
    constexpr sampler sampleTexture(coord::normalized, address::clamp_to_zero, filter::linear);
    return float4(1, 1, 1, symbol.sample(sampleTexture, in.uv).a * in.opacity);
}
