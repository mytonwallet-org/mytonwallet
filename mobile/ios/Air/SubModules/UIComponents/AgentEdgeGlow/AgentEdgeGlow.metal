#include <metal_stdlib>
using namespace metal;

// Matches `AgentEdgeGlowOverlayView.Uniforms`: five float4, 80 bytes.
struct AgentEdgeGlowUniforms {
    float4 frame;       // xy: window size, points; zw: this strip's origin in the window, points
    float4 parameters;  // x: drawable pixels per point; y: display corner radius, points; z: time, seconds; w: opacity
    float4 appearance;  // x: dark appearance; y: reserved; z: how far up from the bottom the drifting lights reach,
                        // points; w: reserved
    float4 blue;        // rgb: the Agent's blue for this appearance, `AgentGlowPalette`'s
    float4 purple;      // rgb: the Agent's violet for this appearance, `AgentGlowPalette`'s
};

struct AgentEdgeGlowVertexOut {
    float4 position [[position]];
};

vertex AgentEdgeGlowVertexOut agentEdgeGlowVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    AgentEdgeGlowVertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    return out;
}

// The motion repeats every `period` seconds: every stretch and light goes round a whole number of times in it, so
// the time can wrap without a jump.
constant float agentEdgeGlowPeriod = 24.0;
// The edge's light reaches this far in, and fades out over the last points of it
constant float agentEdgeGlowDepth = 32.0;

static float agentEdgeGlowRoundedRectDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Where along the display's border the point of it nearest to `local` lies, in points clockwise from the middle of
// the top edge, and the border's length in `total`
static float agentEdgeGlowAlong(float2 local, float2 halfSize, float radius, thread float &total) {
    float2 inner = max(halfSize - radius, 0.0);
    float arc = M_PI_2_F * radius;
    total = 4.0 * (inner.x + inner.y + arc);
    float2 q = clamp(local, -inner, inner);
    float2 d = local - q;
    float2 border;
    if (length(d) > 1e-3) {
        border = q + normalize(d) * radius;
    } else if (inner.y - abs(local.y) < inner.x - abs(local.x)) {
        border = float2(local.x, sign(local.y) * halfSize.y);
    } else {
        border = float2(sign(local.x) * halfSize.x, local.y);
    }
    if (abs(border.x) <= inner.x) {
        // The top edge, its left half at the end of the loop, or the bottom edge
        return border.y < 0.0
            ? (border.x >= 0.0 ? border.x : total + border.x)
            : 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y - (border.x + inner.x);
    }
    if (abs(border.y) <= inner.y) {
        // The right edge, or the left one
        return border.x > 0.0
            ? inner.x + arc + (border.y + inner.y)
            : 3.0 * inner.x + 3.0 * arc + 2.0 * inner.y + (inner.y - border.y);
    }
    // A corner: the angle clockwise from up around its centre
    float2 centre = sign(border) * inner;
    float2 v = border - centre;
    float angle = atan2(v.x, -v.y);
    if (angle < 0.0) { angle += 2.0 * M_PI_F; }
    if (angle <= M_PI_2_F) { return inner.x + radius * angle; }
    if (angle <= M_PI_F) { return inner.x + arc + 2.0 * inner.y + radius * (angle - M_PI_2_F); }
    if (angle <= 1.5 * M_PI_F) { return 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y + radius * (angle - M_PI_F); }
    return 3.0 * inner.x + 3.0 * arc + 4.0 * inner.y + radius * (angle - 1.5 * M_PI_F);
}

// A bright stretch of the edge that goes round `loops` times a period, from `start` of the way round, `sigma` points
// long on either side
static float agentEdgeGlowStretch(float along, float total, float time, float start, float loops, float sigma) {
    float centre = fract(start + loops * time / agentEdgeGlowPeriod) * total;
    float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
    return exp(-d * d / (2.0 * sigma * sigma));
}

// A soft light spreading over `sigma` points
static float agentEdgeGlowLight(float2 xy, float2 centre, float sigma) {
    float2 d = xy - centre;
    return exp(-dot(d, d) / (2.0 * sigma * sigma));
}

// A slow sway that repeats `cycles` times a period
static float agentEdgeGlowSway(float time, float cycles, float phase) {
    return sin(2.0 * M_PI_F * cycles * time / agentEdgeGlowPeriod + phase);
}

// The display's edge giving off light, as the Agent's field does while it listens: a thin, almost white core line
// along the rounded edge, a short bright bloom and a longer softer haze inward, and blue and purple stretches running
// along it at their own speeds, whitening at their brightest. The edge is brighter toward the bottom and toward both
// sides alike, and faint lights drift behind the composer and the bottom bar, at half the strength they once had.
fragment float4 agentEdgeGlowFragment(
    AgentEdgeGlowVertexOut in [[stage_in]],
    constant AgentEdgeGlowUniforms &u [[buffer(0)]]
) {
    float2 size = u.frame.xy;
    float2 xy = in.position.xy / u.parameters.x + u.frame.zw;
    float2 halfSize = size * 0.5;
    float2 local = xy - halfSize;
    float radius = u.parameters.y;
    float time = u.parameters.z;
    float lightsHeight = u.appearance.z;
    float inset = max(-agentEdgeGlowRoundedRectDistance(local, halfSize, radius), 0.0);
    float fromBottom = size.y - xy.y;
    if (inset >= agentEdgeGlowDepth && fromBottom >= lightsHeight) { return float4(0); }

    float3 blueColor = u.blue.rgb;
    float3 purpleColor = u.purple.rgb;

    float3 color = float3(0.0);
    float alpha = 0.0;
    if (inset < agentEdgeGlowDepth) {
        float total;
        float along = agentEdgeGlowAlong(local, halfSize, radius, total);
        // Shorter stretches than the lights of the past, each at its own speed, some going the other way
        float blue = agentEdgeGlowStretch(along, total, time, 0.0, 7.0, 72.0)
            + 0.8 * agentEdgeGlowStretch(along, total, time, 0.55, -4.0, 88.0)
            + 0.7 * agentEdgeGlowStretch(along, total, time, 0.2, 9.0, 52.0);
        float purple = 0.9 * agentEdgeGlowStretch(along, total, time, 0.3, 5.0, 64.0)
            + 0.8 * agentEdgeGlowStretch(along, total, time, 0.8, -3.0, 80.0);
        float stretches = blue + purple;

        float down = clamp(xy.y / size.y, 0.0, 1.0);
        // As bright near either side, together as much as the leading side alone once had
        float fromSide = min(xy.x, size.x - xy.x);
        float nearSide = exp(-max(fromSide, 0.0) / 120.0);
        float base = 0.3 + 0.45 * down * down + 0.175 * nearSide;
        float intensity = base * (0.25 + 1.5 * stretches);

        // Between the stretches the edge keeps a little of both colours
        float3 stretchColor = (blueColor * blue + purpleColor * purple + 0.06 * (blueColor + purpleColor))
            / (stretches + 0.12);
        float core = exp(-inset * inset / (2.0 * 0.9 * 0.9));
        float bloom = exp(-inset / 4.5);
        float haze = 0.4 * exp(-inset / 13.0);
        float fade = 1.0 - smoothstep(0.6 * agentEdgeGlowDepth, agentEdgeGlowDepth, inset);
        float glow = (bloom + haze) * intensity;
        float coreAlpha = clamp(core * intensity, 0.0, 1.0);
        float glowAlpha = clamp(glow * fade, 0.0, 0.9);
        // The core whitens the brighter it is, and so does the bloom at its brightest
        float3 coreColor = mix(stretchColor, float3(1.0), clamp(0.5 + 0.4 * intensity, 0.0, 0.92));
        float3 glowColor = mix(stretchColor, float3(1.0), clamp((glow - 0.9) * 0.5, 0.0, 0.5));
        color = coreColor * coreAlpha + glowColor * glowAlpha * (1.0 - coreAlpha);
        alpha = coreAlpha + glowAlpha * (1.0 - coreAlpha);
    }
    if (fromBottom < lightsHeight) {
        // Large faint lights a little inside the screen, swaying under the edge's light, each a few times a period, at
        // half strength under and around the composer. The two side ones mirror each other in place, size and
        // strength, so neither side is favoured.
        float2 first = float2(
            size.x * (0.28 + 0.19 * agentEdgeGlowSway(time, 2.0, 0.0)),
            size.y - lightsHeight * (0.45 + 0.08 * agentEdgeGlowSway(time, 4.0, 1.0))
        );
        float2 second = float2(
            size.x * (0.72 + 0.19 * agentEdgeGlowSway(time, 2.0, 2.0)),
            size.y - lightsHeight * (0.38 + 0.08 * agentEdgeGlowSway(time, 6.0, 2.5))
        );
        float2 third = float2(
            size.x * (0.5 + 0.32 * agentEdgeGlowSway(time, 4.0, 4.0)),
            size.y - lightsHeight * (0.58 + 0.06 * agentEdgeGlowSway(time, 2.0, 3.0))
        );
        float firstLight = agentEdgeGlowLight(xy, first, 0.52 * lightsHeight);
        float secondLight = agentEdgeGlowLight(xy, second, 0.52 * lightsHeight);
        float thirdLight = agentEdgeGlowLight(xy, third, 0.62 * lightsHeight);
        float blueLight = 0.21 * firstLight + 0.15 * thirdLight;
        float purpleLight = 0.21 * secondLight;
        float fade = 1.0 - smoothstep(0.5 * lightsHeight, lightsHeight, fromBottom);
        float lightsAlpha = 0.5 * clamp((blueLight + purpleLight) * fade, 0.0, 0.35);
        float3 lightsColor = (blueColor * blueLight + purpleColor * purpleLight) / max(blueLight + purpleLight, 1e-4);
        color += lightsColor * lightsAlpha * (1.0 - alpha);
        alpha += lightsAlpha * (1.0 - alpha);
    }
    return float4(color, alpha) * u.parameters.w;
}
