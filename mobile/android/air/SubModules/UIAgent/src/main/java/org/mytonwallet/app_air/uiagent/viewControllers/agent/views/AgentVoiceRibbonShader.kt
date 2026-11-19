package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

/**
 * The voice ribbon's AGSL, as `AgentVoiceRibbon.metal` on iOS: a braid of one to three silk strands of light that comes
 * out of the Stop circle and fades out before it and before the ✕ pill. The braid's cross-sections come from
 * [AgentVoiceRibbonModel.fillSections] through `sections`, a bitmap two rows high with one column per [SECTION_SPACING]
 * dp of ribbon x: the first row holds the axis in red and green and the level in blue, the second the radius in red
 * and green and the opacity in blue. Lengths are in dp; ribbon x starts `span.w` dp before the view's leading edge.
 */
internal val AGENT_VOICE_RIBBON_SHADER = """
uniform shader sections;
uniform float4 canvas;      // x: width; y: height, in dp; z: px per dp; w: 1 for right to left
uniform float4 span;        // Ribbon x of: the far end; where its fade is over; the Stop circle's centre; the view's
                            // leading edge
uniform float4 sectionGrid; // x: ribbon x of the first column; y: dp between columns; z: column count
uniform float4 clocks;      // x: braid phase; y: silk phase; z: bend phase; w: breath clock, seconds
uniform float4 levels;      // x: fast level; y: slow level; z: 1 with Reduce Motion
uniform float4 transition;  // y: opacity; z: slide into Send; w: desaturation
uniform float4 braid;       // x: strand count; y: twist; z: irregularity; w: spread between strands
uniform float4 radius;      // z: height limit
uniform float4 strand;      // x: half-width at rest; y: its growth; z: silk twist; w: brightness of far strands
uniform float4 bend;        // z: breath amount
uniform float2 flare;       // x: extra twist at Stop; y: birth zone length
uniform float4 light;       // x: core brightness; y: core width; z: glow width; w: glow strength
uniform float3 specular;    // x: glint on crests; y: whitening; z: 1 for the dark theme
uniform float4 deepColor;
uniform float4 coreColor;
uniform float4 glowColor;
uniform float4 hotColor;

const float STOP_RADIUS = 20.0;
const float PI = 3.14159265;

float decodeWide(half4 texel) {
    float high = floor(float(texel.r) * 255.0 + 0.5);
    float low = floor(float(texel.g) * 255.0 + 0.5);
    return (high * 256.0 + low) / 65535.0;
}

// The section at ribbon x: axis, radius, level and opacity, linearly between columns
float4 readSection(float x) {
    float position = clamp((x - sectionGrid.x) / sectionGrid.y, 0.0, sectionGrid.z - 1.001);
    float column = floor(position);
    float amount = position - column;
    half4 first0 = sections.eval(float2(column + 0.5, 0.5));
    half4 first1 = sections.eval(float2(column + 1.5, 0.5));
    half4 second0 = sections.eval(float2(column + 0.5, 1.5));
    half4 second1 = sections.eval(float2(column + 1.5, 1.5));
    float4 a = float4(decodeWide(first0) * 64.0 - 32.0, decodeWide(second0) * 64.0, 0.0, 0.0);
    a.zw = float2(float(first0.b), float(second0.b));
    float4 b = float4(decodeWide(first1) * 64.0 - 32.0, decodeWide(second1) * 64.0, 0.0, 0.0);
    b.zw = float2(float(first1.b), float(second1.b));
    return mix(a, b, amount);
}

float getFlare(float x) {
    return 1.0 - smoothstep(-6.0, 3.0 * flare.y, span.z - STOP_RADIUS - x);
}

float tanhOf(float value) {
    float square = exp(2.0 * clamp(value, -10.0, 10.0));
    return (square - 1.0) / (square + 1.0);
}

// The strand's y from the view's middle and its depth, 1 nearest to the viewer and -1 farthest
float2 getStrand(float4 section, float x, float index) {
    float count = braid.x;
    float offset = index - (count - 1.0) * 0.5;
    float wobble = 0.10 * sin(x / 37.0 + index * 2.0 + clocks.z * 1.3);
    float strandRadius = section.y * (1.0 + braid.w * offset + wobble);
    float phase = braid.y * x + braid.z * sin(x / 53.0 + clocks.z * 0.7) + flare.x * getFlare(x)
        + clocks.x + index * 2.0 * PI / count;
    float y = section.x + strandRadius * sin(phase);
    return float2(radius.z * tanhOf(y / radius.z), cos(phase));
}

float3 desaturate(float3 color, float amount) {
    return mix(color, float3(dot(color, float3(0.299, 0.587, 0.114))), amount * 0.7);
}

half4 main(float2 fragCoord) {
    float2 location = fragCoord / canvas.z;
    if (canvas.w > 0.5) {
        location.x = canvas.x - location.x;
    }
    location.x += span.w;
    float y = location.y - canvas.y * 0.5;
    float antialiasing = 0.75 / canvas.z;
    bool isDark = specular.z > 0.5;
    bool isReduceMotion = levels.z > 0.5;
    float fastLevel = levels.x;
    float farEnd = span.x;
    float stopCenter = span.z;
    // Sending slides the whole thread into the Send pill
    float x = location.x - transition.z * 90.0;

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
    brightness *= 1.0 - 0.12 * bend.z * (0.5 + 0.5 * sin(clocks.w * 1.3)) * (1.0 - fastLevel);

    if (x < stopCenter + 2.0 && x > farEnd - 4.0) {
        float4 section = readSection(x);
        float4 nextSection = readSection(x + 0.75);
        float sectionFlare = getFlare(x);
        float level = isReduceMotion ? 0.25 : mix(section.z, fastLevel, sectionFlare);
        float sectionOpacity = section.w;
        if (abs(y) < section.y * 1.5 + abs(section.x) + 4.0 * light.z + 6.0) {
            // Light pooled inside the braid
            float fromAxis = y - section.x;
            float coreWidth = min(0.8 + light.y * section.y, 9.0);
            float core = exp(-fromAxis * fromAxis / (coreWidth * coreWidth))
                * (0.08 + light.x * level + 0.10 * levels.y) * sectionOpacity * brightness;
            if (isDark) {
                emitted += mix(coreColor.rgb, glowColor.rgb, 0.4) * core * 1.2;
            } else {
                float coreAlpha = clamp(core * 0.9, 0.0, 0.4);
                layers[0] = float4(mix(glowColor.rgb, coreColor.rgb, 0.3), coreAlpha);
                depths[0] = -1.5;
            }

            for (int index = 0; index < 3; index++) {
                if (float(index) >= braid.x - 0.5) {
                    break;
                }
                float strandIndex = float(index);
                float2 strandPoint = getStrand(section, x, strandIndex);
                float2 nextStrand = getStrand(nextSection, x + 0.75, strandIndex);
                float slope = (nextStrand.x - strandPoint.x) / 0.75;
                float fromStrand = (y - strandPoint.x) / sqrt(1.0 + slope * slope);
                float depth = strandPoint.y;
                float front = 0.5 + 0.5 * depth;
                float width = (strand.x + strand.y * level) * mix(0.55, 1.0, front);
                // The silk strand's own twist
                float twist = x * strand.z + clocks.y + strandIndex * 2.1;
                float twistCos = cos(twist);
                float twistSin = sin(twist);
                float halfWidth = max(width * abs(twistCos), 0.3);
                float distance = abs(fromStrand);
                float edge = smoothstep(halfWidth - antialiasing, halfWidth + antialiasing, distance);
                float inside = 1.0 - edge;
                float across = clamp(fromStrand / halfWidth, -1.0, 1.0);
                float sheenOffset = (across - 0.7 * twistSin) / 0.45;
                float sheen = exp(-sheenOffset * sheenOffset) * abs(twistCos);
                float glintOffset = fromStrand / (halfWidth + 0.6);
                float glint = pow(max(depth, 0.0), 10.0) * exp(-glintOffset * glintOffset);
                // The glow's distance takes at most this slope, so steep turns at Stop do not smear it vertically
                float glowDistance = abs(y - strandPoint.x) / sqrt(1.0 + min(slope * slope, 2.25));
                float glow = exp(-glowDistance / (light.z * (1.0 + 2.2 * level)))
                    * light.w * (0.45 + 0.9 * level);
                float depthLight = mix(strand.w, 1.0, front);
                float strandOpacity = sectionOpacity * brightness;
                float shine = glint * specular.x * (0.3 + 0.9 * level) * strandOpacity;
                if (isDark) {
                    float3 base = index == 0
                        ? coreColor.rgb
                        : (index == 1 ? glowColor.rgb : mix(coreColor.rgb, deepColor.rgb, 0.5));
                    float strandLight = (inside * (0.35 + 0.65 * sheen) + glow) * depthLight;
                    emitted += base * strandLight * strandOpacity;
                    whiteness += shine;
                } else {
                    float3 base = index == 0
                        ? coreColor.rgb
                        : (index == 1
                            ? mix(deepColor.rgb, coreColor.rgb, 0.3)
                            : mix(coreColor.rgb, glowColor.rgb, 0.35));
                    // Far strands are lighter
                    base = mix(base, glowColor.rgb, (1.0 - front) * 0.5);
                    float strandAlpha = clamp(
                        inside * mix(strand.w + 0.15, 0.95, front) + glow * 0.55 * depthLight,
                        0.0,
                        1.0
                    ) * strandOpacity;
                    float3 strandColor = mix(
                        base,
                        mix(glowColor.rgb, hotColor.rgb, 0.5),
                        clamp(shine * 0.7 + sheen * 0.25 * strandOpacity, 0.0, 0.85) * specular.y
                    );
                    layers[index + 1] = float4(strandColor, strandAlpha);
                    depths[index + 1] = depth;
                }
            }
        }
    }

    float opacity = transition.y;
    float desaturation = transition.w;
    if (isDark) {
        float peak = max(emitted.r, max(emitted.g, emitted.b));
        // Tone-mapped by the brightest channel, so the hue stays
        float3 color = emitted * (1.0 - exp(-1.5 * peak)) / max(peak, 0.0001);
        float3 white = mix(glowColor.rgb, hotColor.rgb, specular.y) * (1.0 - exp(-1.4 * whiteness));
        color = color + white * (1.0 - color);
        color = desaturate(color, desaturation);
        return half4(float4(color, clamp(max(color.r, max(color.g, color.b)), 0.0, 1.0)) * opacity);
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
    float3 straight = desaturate(color / max(alpha, 0.0001), desaturation);
    return half4(float4(straight * alpha, alpha) * opacity);
}
"""

/** dp of ribbon x between the columns of the shader's `sections` */
internal const val SECTION_SPACING = 1f
