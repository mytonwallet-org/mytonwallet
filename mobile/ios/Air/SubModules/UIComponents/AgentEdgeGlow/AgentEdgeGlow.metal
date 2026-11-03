#include <metal_stdlib>
using namespace metal;

// Matches `AgentEdgeGlowOverlayView.Uniforms`: three float4, 48 bytes.
struct AgentEdgeGlowUniforms {
    float4 frame;       // xy: window size, points; zw: this strip's origin in the window, points
    float4 parameters;  // x: drawable pixels per point; y: display corner radius, points; z: time, seconds; w: opacity
    float4 appearance;  // x: dark appearance; yzw: reserved
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

static float agentEdgeGlowRoundedRectDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// One colour blob along the perimeter: cos² over a little less than half of the loop.
static float agentEdgeGlowBlob(float p, float centre) {
    float dp = abs(fract(p - centre + 0.5) - 0.5);
    const float halfWidth = 0.2375;
    if (dp >= halfWidth) { return 0.0; }
    float c = cos(M_PI_2_F * dp / halfWidth);
    return c * c;
}

fragment float4 agentEdgeGlowFragment(
    AgentEdgeGlowVertexOut in [[stage_in]],
    constant AgentEdgeGlowUniforms &u [[buffer(0)]]
) {
    float2 size = u.frame.xy;
    float2 windowPoint = in.position.xy / u.parameters.x + u.frame.zw;
    float2 halfSize = size * 0.5;
    float2 local = windowPoint - halfSize;
    // Points inward from the display's rounded edge.
    float inset = -agentEdgeGlowRoundedRectDistance(local, halfSize, u.parameters.y);
    if (inset > 30.0) { return float4(0); }
    inset = max(inset, 0.0);

    // Radial projection onto the unit square: every side takes the same share of the loop, clockwise from the
    // middle of the top edge (0) through the right (0.25), the bottom (0.5) and the left (0.75).
    float2 uv = local / size;
    float2 s = uv / max(max(abs(uv.x), abs(uv.y)), 1e-5) * 0.5;
    bool isVerticalSide = abs(s.x) >= abs(s.y);
    float p;
    if (!isVerticalSide && s.y < 0.0) {
        p = s.x * 0.25;
        if (p < 0.0) { p += 1.0; }
    } else if (isVerticalSide && s.x > 0.0) {
        p = 0.125 + (s.y + 0.5) * 0.25;
    } else if (!isVerticalSide) {
        p = 0.375 + (0.5 - s.x) * 0.25;
    } else {
        p = 0.625 + (0.5 - s.y) * 0.25;
    }

    // A full loop takes 2.667 s; the purple blob runs half a loop behind the blue one.
    float blueCentre = fract(u.parameters.z / 2.667 + 0.125);
    float blue = agentEdgeGlowBlob(p, blueCentre);
    float purple = agentEdgeGlowBlob(p, blueCentre + 0.5);
    float weight = min(1.0, blue + purple);

    // Gaussian falloff inward (sigma 8 pt). The long sides are dimmer except near the corners, and within about
    // one corner radius of a corner the glow is a quarter brighter than its colour, as a blurred stroke is there.
    const float sigma = 8.0;
    float falloff = exp(-(inset * inset) / (2.0 * sigma * sigma));
    bool isLongSide = isVerticalSide == (size.y >= size.x);
    float alongEdge = max(halfSize.x - abs(local.x), halfSize.y - abs(local.y));
    float cornerZone = max(u.parameters.y, 24.0);
    float corner = 1.0 - smoothstep(0.25 * cornerZone, cornerZone, alongEdge);
    float sideGain = isLongSide ? 0.8 + 0.2 * (1.0 - smoothstep(20.0, 90.0, alongEdge)) : 1.0;
    float intensity = falloff * sideGain * (1.0 + 0.25 * corner);
    float opacity = u.parameters.w;

    if (u.appearance.x > 0.5) {
        float3 blueColor = float3(5.0, 109.0, 205.0) / 255.0;
        float3 purpleColor = float3(144.0, 70.0, 203.0) / 255.0;
        float3 color = (blueColor * blue + purpleColor * purple) / max(blue + purple, 1e-4);
        // Between the blobs the content shows through; above full intensity the colour itself brightens.
        float strength = intensity * weight;
        return float4(color * strength, min(strength, 1.0)) * opacity;
    }
    float3 blueColor = float3(50.0, 158.0, 255.0) / 255.0;
    float3 purpleColor = float3(190.0, 118.0, 253.0) / 255.0;
    float3 haze = float3(244.0, 245.0, 252.0) / 255.0;
    float3 blobColor = (blueColor * blue + purpleColor * purple) / max(blue + purple, 1e-4);
    // Between the blobs a white haze runs along the edge; above full intensity the colour deepens away from it.
    float coverage = 0.95 * intensity;
    float3 band = saturate(mix(haze, blobColor, weight * max(coverage, 1.0)));
    float alpha = min(coverage, 1.0);
    return float4(band * alpha, alpha) * opacity;
}
