#include <metal_stdlib>
using namespace metal;

// At time zero every displacement is zero, preserving the original generator artwork.
// The edge envelope fixes the card boundary so the shader never reveals empty pixels.
static float2 cardMotionPosition(float2 position, float2 size, float time, float amount, float seed) {
    float2 uv = position / max(size, float2(1.0));
    float2 edge = sin(M_PI_F * clamp(uv, 0.0, 1.0));
    float envelope = edge.x * edge.y;
    float phase = seed * (2.0 * M_PI_F);
    float2 wave = float2(
        sin(time * 0.7 + uv.y * 5.0 + phase) - sin(uv.y * 5.0 + phase),
        sin(time * 0.53 + uv.x * 4.0 + phase) - sin(uv.x * 4.0 + phase)
    );
    return position + wave * envelope * amount * size.x / 400.0;
}

[[ stitchable ]] float2 cardBackgroundMotion(float2 position, float2 size, float time, float amount, float seed) {
    return cardMotionPosition(position, size, time, amount, seed);
}

static float2 cardBlobOffset(float time, float seed, uint index) {
    float phase = seed * (2 * M_PI_F) + float(index) * 2.0943951;
    float2 radius = float2(18 + 3 * index, 12 + 2 * index);
    return smoothstep(0.0, 2.0, time) * radius
        * float2(sin(time * (0.38 + 0.03 * index) + phase), cos(time * (0.29 + 0.02 * index) + phase));
}

static float3 cardSRGB(float3 color) {
    return select(1.055 * pow(max(color, 0.0), float3(1.0 / 2.4)) - 0.055, color * 12.92, color <= 0.0031308);
}

struct CardVertex {
    float4 position [[position]];
    float2 uv;
};

struct CardUniforms {
    float2 size;
    float time;
    float strength;
    float seed;
    float shine;
    float2 tilt;
    uint shineStyle;
    float linearWidth;
    float brush;
    float spotPadding;
    float blobTime;
    uint blobCount;
    float contrastOpacity;
    float contrastColor;
    uint blobMotion;
    float activity;
    float linearAngle;
};

// Sampling rotates in canonical card points, preserving circles on a wide card.
static float2 cardBlobSamplePosition(float2 uv, constant CardUniforms &u, uint index) {
    float2 point = uv * float2(400, 232);
    if (u.blobMotion == 1) {
        float angle = u.blobTime * (0.7 * 2 * M_PI_F / 40);
        float c = cos(angle), s = sin(angle);
        float2 centered = point - float2(200, 116);
        return float2(c * centered.x + s * centered.y, -s * centered.x + c * centered.y) + float2(200, 116);
    }
    return point - cardBlobOffset(u.blobTime * 0.7, u.seed, index);
}

static float cardLightField(float2 uv, constant CardUniforms &u, texture2d<float> light) {
    if (u.shine <= 0) { return 0; }
    float2 point = (uv - 0.5) * u.size;
    if (u.shineStyle == 2) {
        constexpr sampler sampleSpot(coord::normalized, address::clamp_to_zero, filter::linear);
        float2 center = u.tilt * u.size * 0.5;
        float extent = u.linearWidth * u.size.x;
        return light.sample(sampleSpot, (point - center) / extent + 0.5).a;
    }
    if (u.shineStyle == 0) {
        float angle = -u.linearAngle;
        float2 normal = float2(-sin(angle), cos(angle));
        float width = u.size.x * max(u.linearWidth, 0.02);
        // Include the Gaussian tail so either endpoint clears every card corner.
        float travel = dot(abs(normal), u.size) * 0.5 + width * 1.5;
        float distance = (dot(point, normal) - u.tilt.y * travel) / width;
        return exp(-2.7725887 * distance * distance);
    }
    constexpr sampler sampleLight(coord::normalized, address::clamp_to_edge, filter::linear);
    float direction = u.tilt.x * M_PI_F / 2 + u.tilt.y * M_PI_F / 3;
    float angle = -M_PI_F / 2 + direction;
    float c = cos(angle), s = sin(angle);
    float2 local = float2(c * point.x + s * point.y, -s * point.x + c * point.y) / u.size.x;
    return light.sample(sampleLight, local / 1.5 + 0.5).a;
}

vertex CardVertex cardBackgroundVertex(uint id [[vertex_id]]) {
    const float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    float2 p = positions[id];
    return { float4(p, 0, 1), float2((p.x + 1) * 0.5, (1 - p.y) * 0.5) };
}

fragment float4 cardBackgroundFragment(CardVertex in [[stage_in]], texture2d<float> artwork [[texture(0)]],
                                      texture2d<float> light [[texture(1)]],
                                      texture2d<float> brush [[texture(2)]],
                                      texture2d<float> firstSpot [[texture(3)]],
                                      texture2d<float> secondSpot [[texture(4)]],
                                      texture2d<float> thirdSpot [[texture(5)]],
                                      constant CardUniforms &u [[buffer(0)]]) {
    constexpr sampler sampleArtwork(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 position = cardMotionPosition(in.uv * u.size, u.size, u.time, u.strength, u.seed);
    float4 color = artwork.sample(sampleArtwork, position / max(u.size, float2(1)));
    if (u.shine > 0 || u.brush > 0 || u.blobCount > 0 || u.contrastColor >= 0) {
        float3 srgb = cardSRGB(color.rgb);
        for (uint index = 0; index < u.blobCount; index++) {
            float2 uv = (cardBlobSamplePosition(in.uv, u, index) + u.spotPadding) / (float2(400, 232) + 2 * u.spotPadding);
            // Blurred spot textures contain premultiplied sRGB, matching Canvas compositing.
            float4 spot = index == 0 ? firstSpot.sample(sampleArtwork, uv)
                : index == 1 ? secondSpot.sample(sampleArtwork, uv) : thirdSpot.sample(sampleArtwork, uv);
            srgb = spot.rgb + srgb * (1 - spot.a);
        }
        if (u.contrastColor >= 0) {
            // Keep the original text contrast overlay fixed above the moving spots.
            float radius = length((in.uv - 0.5) * float2(400, 232) / float2(269.69, 158));
            float alpha = radius < 0.25 ? 1 - radius * 0.8
                : radius < 0.75 ? 1.1 - radius * 1.2 : max(0.0, 0.8 - radius * 0.8);
            float3 overlay = select(1 - 2 * (1 - srgb) * (1 - u.contrastColor), 2 * srgb * u.contrastColor, srgb <= 0.5);
            srgb = mix(srgb, overlay, alpha * u.contrastOpacity);
            srgb = mix(srgb, float3(u.contrastColor), alpha * 0.16);
        }
        // The surface grain stays fixed while the color blobs move beneath it.
        if (u.brush > 0) {
            float grain = brush.sample(sampleArtwork, in.uv).r;
            float3 overlay = select(1 - 2 * (1 - srgb) * (1 - grain), 2 * srgb * grain, srgb <= 0.5);
            srgb = mix(srgb, overlay, u.brush);
        }
        if (u.shine > 0) {
            float field = cardLightField(in.uv, u, light);
            srgb = saturate(srgb + field * u.shine);
        }
        color.rgb = select(pow((srgb + 0.055) / 1.055, float3(2.4)), srgb / 12.92, srgb <= 0.04045);
    }
    return color;
}

struct CardStar {
    float2 position;
    float radius;
    float phase;
};

struct CardStarVertex {
    float4 position [[position]];
    float2 local;
    float opacity [[flat]];
};

vertex CardStarVertex cardStarVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                    constant CardUniforms &u [[buffer(0)]], constant CardStar *stars [[buffer(1)]],
                                    texture2d<float> light [[texture(0)]]) {
    const float2 corners[] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    CardStar star = stars[instance];
    float2 uv = star.position / float2(400, 232);
    float twinkle = smoothstep(0.15, 1.0, 0.5 + 0.5 * sin(u.blobTime * (0.28 + fract(star.phase) * 0.14) + star.phase));
    // Use exactly the same light coordinates as the background, including touch tilt.
    float activation = cardLightField(uv, u, light) * min(1.0, u.shine * 5) * (0.35 + 0.65 * u.activity);
    float radius = star.radius * (0.15 + 0.85 * twinkle + 0.45 * activation + 0.1 * u.activity);
    float2 local = corners[id];
    float2 point = (star.position + local * radius) / float2(400, 232);
    return { float4(point.x * 2 - 1, 1 - point.y * 2, 0, 1), local,
             saturate(twinkle * 0.65 + activation * 0.7 + u.activity * 0.12) };
}

fragment float4 cardStarFragment(CardStarVertex in [[stage_in]]) {
    float distance = sqrt(abs(in.local.x)) + sqrt(abs(in.local.y));
    float aa = max(fwidth(distance), 0.02);
    float alpha = (1 - smoothstep(1 - aa, 1 + aa, distance)) * in.opacity;
    return float4(1, 1, 1, alpha);
}
