#include <metal_stdlib>
using namespace metal;

// The Stop circle is 32 points wide
constant float agentVoiceRibbonStopRadius = 16.0;
// The thread fades out this far before the Stop circle, as far as it starts after the ✕ pill
constant float agentVoiceRibbonStopGap = 12.0;

// Matches `AgentVoiceRibbonUniforms` in AgentVoiceRibbonModel.swift: 32 float4, 512 bytes. Lengths are in points.
// Ribbon x grows from the leading side towards the Stop circle and starts `layout.w` points before the view's leading
// edge, at the field's leading edge, where the prototype starts it; y grows down from the view's top.
struct AgentVoiceRibbonUniforms {
    float4 canvas;      // x: the view's width; y: its height; z: drawable pixels per point; w: 1 for right to left
    float4 layout;      // Ribbon x of: the far end; where the fade at the far end is over; the Stop circle's centre;
                        // the view's leading edge
    float4 clocks;      // x: braid phase; y: silk phase; z: bend phase; w: breath clock, seconds
    float4 levels;      // x: fast level; y: slow level; z: 1 with Reduce Motion; w: age of `history[1]`, seconds
    float4 transition;  // x: how far the thread is drawn out; y: opacity; z: slide into Send; w: desaturation
    float4 braid;       // x: strand count; y: twist, radians per point; z: irregularity; w: spread between strands
    float4 radius;      // x: braid half-height at rest; y: its growth at full voice; z: height limit; w: taper
    float4 strand;      // x: strand half-width at rest; y: its growth at full voice; z: silk twist, radians per point;
                        // w: brightness of far strands
    float4 bend;        // x: bend; y: bend length; z: breath amount; w: how long a syllable takes to cross, seconds
    float4 flare;       // x: opening at Stop; y: extra twist at Stop, radians; z: birth zone length
    float4 light;       // x: core brightness; y: core width; z: glow width; w: glow strength
    float4 specular;    // x: glint on crests; y: whitening; z: 1 for the dark theme
    float4 deep;        // rgb: palette colours, sRGB-encoded
    float4 core;
    float4 glow;
    float4 hot;
    float4 history[16]; // 64 samples of the syllable level at 60 Hz, newest first
};

struct AgentVoiceRibbonVertexOut {
    float4 position [[position]];
};

// One cross-section of the braid at some x
struct AgentVoiceRibbonSection {
    float center;   // The braid's axis, points from the view's middle
    float radius;
    float level;    // The syllable level that reached this x
    float flare;    // 1 in the birth zone at the Stop circle, 0 away from it
    float opacity;
};

static float agentVoiceRibbonNoise(float t);
static float agentVoiceRibbonHistory(constant AgentVoiceRibbonUniforms &uniforms, float age);
static float agentVoiceRibbonHistorySample(constant AgentVoiceRibbonUniforms &uniforms, float age);
static AgentVoiceRibbonSection agentVoiceRibbonSection(constant AgentVoiceRibbonUniforms &uniforms, float x);
static float2 agentVoiceRibbonStrand(
    constant AgentVoiceRibbonUniforms &uniforms,
    AgentVoiceRibbonSection section,
    float x,
    int index
);
static float3 agentVoiceRibbonDesaturate(float3 color, float amount);

vertex AgentVoiceRibbonVertexOut agentVoiceRibbonVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    AgentVoiceRibbonVertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    return out;
}

// A braid of one to three silk strands of light that comes out of the Stop circle and dissolves before the ✕ pill.
// The output is premultiplied, written over a cleared transparent drawable.
fragment float4 agentVoiceRibbonFragment(
    AgentVoiceRibbonVertexOut in [[stage_in]],
    constant AgentVoiceRibbonUniforms &uniforms [[buffer(0)]]
) {
    float2 location = in.position.xy / uniforms.canvas.z;
    if (uniforms.canvas.w > 0.5) {
        location.x = uniforms.canvas.x - location.x;
    }
    location.x += uniforms.layout.w;
    float y = location.y - uniforms.canvas.y * 0.5;
    float antialiasing = 0.75 / uniforms.canvas.z;
    bool isDark = uniforms.specular.z > 0.5;
    bool isReduceMotion = uniforms.levels.z > 0.5;
    float fastLevel = uniforms.levels.x;
    float farEnd = uniforms.layout.x;
    float stopCenter = uniforms.layout.z;
    // Sending slides the whole thread into the Send pill
    float x = location.x - uniforms.transition.z * 90.0;
    float3 deepColor = uniforms.deep.rgb;
    float3 coreColor = uniforms.core.rgb;
    float3 glowColor = uniforms.glow.rgb;
    float3 hotColor = uniforms.hot.rgb;

    // The dark theme adds light; the light theme stacks the core and the strands back to front
    float3 emitted = float3(0.0);
    float whiteness = 0.0;
    float4 layers[4];
    float depths[4];
    for (int index = 0; index < 4; index++) {
        layers[index] = float4(0.0);
        depths[index] = -2.0;
    }
    float brightness = isReduceMotion ? 0.45 + 0.75 * fastLevel : 1.0;
    // The light never reaches the glass's edge
    brightness *= 1.0 - smoothstep(17.0, 23.0, abs(y));
    brightness *= 1.0 - 0.12 * uniforms.bend.z * (0.5 + 0.5 * sin(uniforms.clocks.w * 1.3)) * (1.0 - fastLevel);

    if (x < stopCenter + 2.0 && x > farEnd - 4.0) {
        AgentVoiceRibbonSection section = agentVoiceRibbonSection(uniforms, x);
        AgentVoiceRibbonSection nextSection = agentVoiceRibbonSection(uniforms, x + 0.75);
        float level = isReduceMotion ? 0.25 : mix(section.level, fastLevel, section.flare);
        if (abs(y) < section.radius * 1.5 + abs(section.center) + 4.0 * uniforms.light.z + 6.0) {
            // Light pooled inside the braid
            float fromAxis = y - section.center;
            float coreWidth = min(0.8 + uniforms.light.y * section.radius, 9.0);
            float core = exp(-fromAxis * fromAxis / (coreWidth * coreWidth))
                * (0.08 + uniforms.light.x * level + 0.10 * uniforms.levels.y) * section.opacity * brightness;
            if (isDark) {
                emitted += mix(coreColor, glowColor, 0.4) * core * 1.2;
            } else {
                layers[0] = float4(mix(glowColor, coreColor, 0.3), clamp(core * 0.9, 0.0, 0.4));
                depths[0] = -1.5;
            }

            int strandCount = int(uniforms.braid.x + 0.5);
            for (int index = 0; index < 3; index++) {
                if (index >= strandCount) {
                    break;
                }
                float2 strand = agentVoiceRibbonStrand(uniforms, section, x, index);
                float2 nextStrand = agentVoiceRibbonStrand(uniforms, nextSection, x + 0.75, index);
                float slope = (nextStrand.x - strand.x) / 0.75;
                float fromStrand = (y - strand.x) / sqrt(1.0 + slope * slope);
                float depth = strand.y;
                float front = 0.5 + 0.5 * depth;
                float width = (uniforms.strand.x + uniforms.strand.y * level) * mix(0.55, 1.0, front);
                // The silk strand's own twist
                float twist = x * uniforms.strand.z + uniforms.clocks.y + float(index) * 2.1;
                float twistCos = cos(twist);
                float twistSin = sin(twist);
                float halfWidth = max(width * abs(twistCos), 0.3);
                float inside = 1.0 - smoothstep(halfWidth - antialiasing, halfWidth + antialiasing, abs(fromStrand));
                float across = clamp(fromStrand / halfWidth, -1.0, 1.0);
                float sheenOffset = (across - 0.7 * twistSin) / 0.45;
                float sheen = exp(-sheenOffset * sheenOffset) * abs(twistCos);
                float glintOffset = fromStrand / (halfWidth + 0.6);
                float glint = powr(max(depth, 0.0), 10.0) * exp(-glintOffset * glintOffset);
                // The glow's distance takes at most this slope, so steep turns at Stop do not smear it vertically
                float glowDistance = abs(y - strand.x) / sqrt(1.0 + min(slope * slope, 2.25));
                float glow = exp(-glowDistance / (uniforms.light.z * (1.0 + 2.2 * level)))
                    * uniforms.light.w * (0.45 + 0.9 * level);
                float depthLight = mix(uniforms.strand.w, 1.0, front);
                float strandOpacity = section.opacity * brightness;
                float specular = glint * uniforms.specular.x * (0.3 + 0.9 * level) * strandOpacity;
                if (isDark) {
                    float3 base = index == 0 ? coreColor : (index == 1 ? glowColor : mix(coreColor, deepColor, 0.5));
                    emitted += base * (inside * (0.35 + 0.65 * sheen) * depthLight + glow * depthLight) * strandOpacity;
                    whiteness += specular;
                } else {
                    float3 base = index == 0
                        ? coreColor
                        : (index == 1 ? mix(deepColor, coreColor, 0.3) : mix(coreColor, glowColor, 0.35));
                    // Far strands are lighter
                    base = mix(base, glowColor, (1.0 - front) * 0.5);
                    float strandAlpha = clamp(
                        inside * mix(uniforms.strand.w + 0.15, 0.95, front) + glow * 0.55 * depthLight, 0.0, 1.0
                    ) * strandOpacity;
                    float3 strandColor = mix(
                        base,
                        mix(glowColor, hotColor, 0.5),
                        clamp(specular * 0.7 + sheen * 0.25 * strandOpacity, 0.0, 0.85) * uniforms.specular.y
                    );
                    layers[index + 1] = float4(strandColor, strandAlpha);
                    depths[index + 1] = depth;
                }
            }
        }
    }

    float opacity = uniforms.transition.y;
    float desaturation = uniforms.transition.w;
    if (isDark) {
        float peak = max(emitted.r, max(emitted.g, emitted.b));
        // Tone-mapped by the brightest channel, so the hue stays
        float3 color = emitted * (1.0 - exp(-1.5 * peak)) / max(peak, 1e-4);
        float3 white = mix(glowColor, hotColor, uniforms.specular.y) * (1.0 - exp(-1.4 * whiteness));
        color = color + white * (1.0 - color);
        color = agentVoiceRibbonDesaturate(color, desaturation);
        return float4(color, clamp(max(color.r, max(color.g, color.b)), 0.0, 1.0)) * opacity;
    }
    // Strands sorted back to front, then composited over each other
    for (int pass = 1; pass < 4; pass++) {
        for (int index = 1; index < 3; index++) {
            if (depths[index] > depths[index + 1]) {
                float4 layer = layers[index];
                layers[index] = layers[index + 1];
                layers[index + 1] = layer;
                float layerDepth = depths[index];
                depths[index] = depths[index + 1];
                depths[index + 1] = layerDepth;
            }
        }
    }
    float3 color = float3(0.0);
    float alpha = 0.0;
    for (int index = 0; index < 4; index++) {
        color = layers[index].rgb * layers[index].a + color * (1.0 - layers[index].a);
        alpha = layers[index].a + alpha * (1.0 - layers[index].a);
    }
    float3 straight = agentVoiceRibbonDesaturate(color / max(alpha, 1e-4), desaturation);
    return float4(straight * alpha, alpha) * opacity;
}

// A smooth wave of three incommensurate sines, from -1 to 1
static float agentVoiceRibbonNoise(float t) {
    return 0.55 * sin(t + 0.3) + 0.30 * sin(2.13 * t + 1.1) + 0.15 * sin(3.71 * t + 2.0);
}

// The syllable level `age` seconds ago, smoothed over neighbouring samples so fast attacks bend without kinks
static float agentVoiceRibbonHistory(constant AgentVoiceRibbonUniforms &uniforms, float age) {
    float spacing = 1.6 / 60.0;
    return (agentVoiceRibbonHistorySample(uniforms, max(age - 2.0 * spacing, 0.0))
        + 4.0 * agentVoiceRibbonHistorySample(uniforms, max(age - spacing, 0.0))
        + 6.0 * agentVoiceRibbonHistorySample(uniforms, age)
        + 4.0 * agentVoiceRibbonHistorySample(uniforms, age + spacing)
        + agentVoiceRibbonHistorySample(uniforms, age + 2.0 * spacing)) / 16.0;
}

// `history[0]` is the current level and `history[1]` is `levels.w` seconds old, each next one 1/60 s older
static float agentVoiceRibbonHistorySample(constant AgentVoiceRibbonUniforms &uniforms, float age) {
    float newestAge = uniforms.levels.w;
    float position = age >= newestAge ? (age - newestAge) * 60.0 + 1.0 : age / max(newestAge, 1e-4);
    position = clamp(position, 0.0, 62.999);
    int index = int(position);
    int nextIndex = index + 1;
    float value = uniforms.history[index >> 2][index & 3];
    float nextValue = uniforms.history[nextIndex >> 2][nextIndex & 3];
    return mix(value, nextValue, position - float(index));
}

static AgentVoiceRibbonSection agentVoiceRibbonSection(constant AgentVoiceRibbonUniforms &uniforms, float x) {
    float farEnd = uniforms.layout.x;
    float stopCenter = uniforms.layout.z;
    float stopRadius = agentVoiceRibbonStopRadius;
    bool isReduceMotion = uniforms.levels.z > 0.5;
    float ribbonLength = stopCenter - stopRadius - farEnd;
    float fromStop = stopCenter - stopRadius - x;
    float along = clamp(fromStop / ribbonLength, 0.0, 1.0);
    AgentVoiceRibbonSection section;
    // The voice travels from Stop towards the far end
    section.level = isReduceMotion ? 0.0 : agentVoiceRibbonHistory(uniforms, along * uniforms.bend.w);
    float nearEnd = stopCenter - stopRadius - agentVoiceRibbonStopGap;
    float fadeLength = uniforms.layout.y - farEnd;
    float fade = smoothstep(farEnd, uniforms.layout.y, x) * (1.0 - smoothstep(nearEnd - fadeLength, nearEnd, x));
    // The tip of the thread being drawn out of Stop or gathered back into it
    float tip = uniforms.transition.x * (ribbonLength + 30.0) - 8.0;
    float visibility = 1.0 - smoothstep(tip - 24.0, tip, fromStop);
    section.flare = 1.0 - smoothstep(-6.0, 3.0 * uniforms.flare.z, fromStop);
    float radius = isReduceMotion
        ? uniforms.radius.x + 0.25 * uniforms.radius.y
        : uniforms.radius.x * (1.0 + uniforms.bend.z * sin(uniforms.clocks.w * 1.1 - along * 5.0))
            + uniforms.radius.y * powr(max(section.level, 0.0), 0.8);
    radius = mix(radius, uniforms.radius.x + uniforms.flare.x * (0.35 + 0.65 * uniforms.levels.x), section.flare * 0.85);
    section.radius = radius * mix(1.0, 1.0 - uniforms.radius.w, smoothstep(0.1, 1.0, along))
        * mix(0.25, 1.0, fade) * visibility * (1.0 - uniforms.transition.z);
    section.center = uniforms.bend.x * (1.0 + 1.5 * uniforms.levels.y)
        * agentVoiceRibbonNoise(x / uniforms.bend.y + uniforms.clocks.z) * smoothstep(0.0, 40.0, fromStop) * fade;
    section.opacity = fade * visibility;
    return section;
}

// The strand's y, points from the view's middle, and its depth, 1 nearest to the viewer and -1 farthest
static float2 agentVoiceRibbonStrand(
    constant AgentVoiceRibbonUniforms &uniforms,
    AgentVoiceRibbonSection section,
    float x,
    int index
) {
    float count = uniforms.braid.x;
    float strandIndex = float(index);
    float offset = strandIndex - (count - 1.0) * 0.5;
    float radius = section.radius
        * (1.0 + uniforms.braid.w * offset + 0.10 * sin(x / 37.0 + strandIndex * 2.0 + uniforms.clocks.z * 1.3));
    float phase = uniforms.braid.y * x + uniforms.braid.z * sin(x / 53.0 + uniforms.clocks.z * 0.7)
        + uniforms.flare.y * section.flare + uniforms.clocks.x + strandIndex * 2.0 * M_PI_F / count;
    float y = section.center + radius * sin(phase);
    float limit = uniforms.radius.z;
    return float2(limit * tanh(y / limit), cos(phase));
}

static float3 agentVoiceRibbonDesaturate(float3 color, float amount) {
    return mix(color, float3(dot(color, float3(0.299, 0.587, 0.114))), amount * 0.7);
}
