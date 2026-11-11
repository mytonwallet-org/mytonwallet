#include <metal_stdlib>
using namespace metal;

// Matches `AgentFieldGlowView.Uniforms`: three float4, 48 bytes.
struct AgentFieldGlowUniforms {
    float4 geometry;  // xy: the field's size, points; z: drawable pixels per point; w: corner radius, points
    float4 motion;    // x: time, seconds; y: opacity; z: the leading side, 0 for the left and 1 for the right;
                      // w: how far the canvas reaches beyond the field on every side, points
    float4 tint;      // rgb: the accent colour
};

struct AgentFieldGlowVertexOut {
    float4 position [[position]];
};

vertex AgentFieldGlowVertexOut agentFieldGlowVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    AgentFieldGlowVertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    return out;
}

static float agentFieldGlowRoundedRectDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// A soft light spreading over `sigma` points
static float agentFieldGlowLight(float2 xy, float2 centre, float sigma) {
    float2 d = xy - centre;
    return exp(-dot(d, d) / (2.0 * sigma * sigma));
}

// The same light as Android's `AgentFieldGlowView` shader draws, point for point: an edge band brightest at the bottom
// and the leading side, and three lights drifting along the bottom, through the field and up and down the leading side.
fragment float4 agentFieldGlowFragment(
    AgentFieldGlowVertexOut in [[stage_in]],
    constant AgentFieldGlowUniforms &u [[buffer(0)]]
) {
    float2 size = u.geometry.xy;
    float2 xy = in.position.xy / u.geometry.z - u.motion.w;
    float time = u.motion.x;
    float leading = u.motion.z;
    float2 halfSize = size * 0.5;
    float inset = max(-agentFieldGlowRoundedRectDistance(xy - halfSize, halfSize, u.geometry.w), 0.0);
    float leadingDistance = abs(xy.x / size.x - leading) * size.x;
    float down = xy.y / size.y;
    float edgeBand = exp(-inset / 5.0);
    float nearLeading = exp(-leadingDistance / 50.0);

    // A share of the width from the leading side is `abs(leading - share) * size.x`
    float2 bottomCentre = float2(abs(leading - (0.35 + 0.25 * sin(time * 0.55))) * size.x, size.y);
    float2 driftCentre = float2(
        abs(leading - (0.575 + 0.325 * sin(time * 0.37 + 2.0))) * size.x,
        size.y * (0.725 + 0.275 * sin(time * 0.8))
    );
    float2 sideCentre = float2(leading * size.x, size.y * (0.65 + 0.35 * sin(time * 0.45 + 1.0)));
    float bottomLight = agentFieldGlowLight(xy, bottomCentre, 28.0);
    float driftLight = agentFieldGlowLight(xy, driftCentre, 40.0);
    float sideLight = agentFieldGlowLight(xy, sideCentre, 22.0);
    float haze = 0.3 * exp(-(size.y - xy.y) / 22.0) * (0.5 + 0.5 * nearLeading);
    float glow = edgeBand * (0.35 + 1.1 * nearLeading + 0.6 * down)
        * (0.7 + 0.9 * bottomLight + 0.5 * driftLight + 0.6 * sideLight)
        + 0.45 * bottomLight + 0.25 * driftLight + 0.35 * sideLight + haze;
    float alpha = clamp(glow * 0.55, 0.0, 0.92) * u.motion.y;
    // The brightest light whitens
    float3 color = mix(u.tint.rgb, float3(1.0), clamp((glow - 1.1) * 0.35, 0.0, 0.6));
    return float4(color * alpha, alpha);
}

// Where along the field's border the point of it nearest to `local` lies, in points clockwise from the middle of the
// top edge, and the border's length in `total`
static float agentFieldRimAlong(float2 local, float2 halfSize, float radius, thread float &total) {
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

// A bright stretch of the rim centred `centre` points along a border `total` points long
static float agentFieldRimSpot(float along, float centre, float total, float sigma) {
    float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
    return exp(-d * d / (2.0 * sigma * sigma));
}

// The field's border giving off light: a thin, almost white core line along it, a bloom in the accent colour spilling
// out beyond the field and a softer haze inside it. The rim is brightest at the bottom and the leading side, and bright
// stretches run along it.
fragment float4 agentFieldRimFragment(
    AgentFieldGlowVertexOut in [[stage_in]],
    constant AgentFieldGlowUniforms &u [[buffer(0)]]
) {
    float2 size = u.geometry.xy;
    float2 xy = in.position.xy / u.geometry.z - u.motion.w;
    float time = u.motion.x;
    float leading = u.motion.z;
    float2 halfSize = size * 0.5;
    float2 local = xy - halfSize;
    float radius = u.geometry.w;
    float edgeDistance = agentFieldGlowRoundedRectDistance(local, halfSize, radius);
    float total;
    float along = agentFieldRimAlong(local, halfSize, radius, total);

    float down = clamp(xy.y / size.y, 0.0, 1.0);
    float nearLeading = exp(-abs(clamp(xy.x / size.x, 0.0, 1.0) - leading) * size.x / 90.0);
    float base = 0.15 + 0.45 * down + 0.6 * nearLeading;
    float spots = agentFieldRimSpot(along, time * 140.0, total, 60.0)
        + 0.8 * agentFieldRimSpot(along, total * 0.45 - time * 95.0, total, 48.0)
        + 0.6 * agentFieldRimSpot(along, total * 0.7 + time * 60.0, total, 70.0);
    float intensity = base * (0.3 + 1.2 * spots);

    float core = exp(-edgeDistance * edgeDistance / (2.0 * 0.6 * 0.6));
    // The bloom spreads out over a few points and fades on over more, and the haze inside is softer
    float outer = edgeDistance > 0.0 ? exp(-edgeDistance / 7.0) + 0.35 * exp(-edgeDistance / 18.0) : 0.0;
    // It is gone by the canvas's edge
    outer *= 1.0 - smoothstep(0.5 * u.motion.w, u.motion.w, edgeDistance);
    float inner = edgeDistance < 0.0 ? 0.45 * exp(edgeDistance / 9.0) : 0.0;
    float coreAlpha = clamp(core * intensity, 0.0, 1.0);
    float bloomAlpha = clamp((outer + inner) * intensity, 0.0, 0.9);
    // The core whitens the brighter it is
    float3 coreColor = mix(u.tint.rgb, float3(1.0), clamp(0.45 + 0.45 * intensity, 0.0, 0.9));
    float3 bloomColor = mix(u.tint.rgb, float3(1.0), 0.1);
    float3 color = coreColor * coreAlpha + bloomColor * bloomAlpha * (1.0 - coreAlpha);
    float alpha = coreAlpha + bloomAlpha * (1.0 - coreAlpha);
    return float4(color, alpha) * u.motion.y;
}
