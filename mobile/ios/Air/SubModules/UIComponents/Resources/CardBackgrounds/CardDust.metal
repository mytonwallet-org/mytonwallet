#include <metal_stdlib>
using namespace metal;

struct DustUniforms { float2 size; float2 padding; float4 gradient; };
struct DustVertex {
    float4 position [[position]];
    float2 local [[sample_no_perspective]];
    float2 point [[sample_no_perspective]];
    float opacity [[flat]];
};
vertex DustVertex cardDustVertex(uint vid [[vertex_id]], uint instance [[instance_id]],
    constant float4 *particles [[buffer(0)]], constant DustUniforms &u [[buffer(1)]]) {
    constexpr float2 corners[] = {{-1,-1},{1,-1},{-1,1},{1,1}};
    float4 p = particles[instance];
    float2 local = corners[vid];
    float2 point = p.xy + local * p.z;
    return {float4(point.x / u.size.x * 2 - 1, 1 - point.y / u.size.y * 2, 1 - p.w * 0.9, 1), local, point, p.w};
}
fragment float4 cardDustFragment(DustVertex in [[stage_in]], constant DustUniforms &u [[buffer(1)]],
    constant float4 *colors [[buffer(2)]]) {
    if (dot(in.local, in.local) > 1) discard_fragment();
    float t = clamp(distance(in.point, u.gradient.xy) / u.gradient.z, 0.0f, 1.0f) * max(0.0f, u.gradient.w - 1);
    uint index = uint(t), next = min(index + 1, uint(u.gradient.w) - 1);
    float4 color = mix(colors[index], colors[next], fract(t));
    float alpha = color.a * in.opacity;
    return float4(color.rgb * alpha, alpha);
}

// Element disintegration shares the precompiled particle library.
struct ElementFragment { float2 source; float2 destination; float2 bend; float2 size; float4 uv; float4 timing; float4 cloud; };
struct ElementUniforms { float2 size; float progress; float particleSize; float4 blend; };
struct ElementVarying { float4 position [[position]]; float2 uv; float visibility; };
vertex ElementVarying elementVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
    constant ElementFragment *fragments [[buffer(0)]], constant ElementUniforms &u [[buffer(1)]]) {
    const float2 corners[] = {float2(0,0),float2(1,0),float2(0,1),float2(1,0),float2(1,1),float2(0,1)};
    ElementFragment f = fragments[iid]; float2 q = corners[vid];
    float timeline = f.cloud.w >= 0 ? u.progress / u.blend.y : u.progress;
    float t = clamp((timeline-f.timing.x) / f.timing.w, 0.0, 1.0);
    float cubic = t*t*(3-2*t); float quintic = t*t*t*(t*(t*6-15)+10);
    float p = u.blend.z < 0.5 ? mix(t, cubic, u.blend.z*2) : mix(cubic, quintic, (u.blend.z-0.5)*2);
    float blend = clamp((u.progress-u.blend.x)/(u.blend.y-u.blend.x), 0.0, 1.0);
    float cloudMix = blend*blend*blend*(blend*(blend*6-15)+10);
    float2 center = mix(f.source, f.destination, p) + f.bend * sin(p * M_PI_F);
    float2 size = mix(f.size, float2(u.particleSize * f.timing.y), p);
    if (f.cloud.w >= 0) size = mix(size, float2(f.cloud.z), cloudMix);
    float angle = sin(p * M_PI_F) * f.timing.z;
    float2 offset = (q - 0.5) * size;
    offset = float2(offset.x*cos(angle)-offset.y*sin(angle),offset.x*sin(angle)+offset.y*cos(angle));
    float2 position = center + offset;
    ElementVarying out; out.position = float4(position.x/u.size.x*2-1, 1-position.y/u.size.y*2, 0, 1);
    out.uv = f.uv.xy + q*f.uv.zw;
    out.visibility = (1 - cloudMix) * (f.cloud.w >= 0 ? mix(1.0, f.cloud.w, cloudMix) : 1.0);
    return out;
}
fragment float4 elementFragment(ElementVarying in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    return image.sample(sampling, in.uv) * in.visibility;
}
