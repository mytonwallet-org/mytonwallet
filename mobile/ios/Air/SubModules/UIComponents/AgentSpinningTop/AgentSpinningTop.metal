#include <metal_stdlib>
using namespace metal;

// Matches `SpinningTopRenderer.Uniforms`: one float4x4 and five float4, 144 bytes.
struct SpinningTopUniforms {
    float4x4 rotation;  // Model to view
    float4 placement;   // xy: model centre in drawable pixels, y up; z: pixels per model unit; w: drawable height
    float4 parameters;  // x: drawable width; y: hold strength 0…1; z: dark appearance; w: has backdrop
    float4 backdrop;    // Backdrop rectangle in drawable pixels, y down: origin, size
    float4 material;    // x: highlight boost; y: opacity floor; zw: the box centre relative to the model origin, view units
    float4 effects;     // x: iridescence 0…1; y: motion-blur sweep, radians; z: speed streaks 0…1; w: reflection opacity
};

struct SpinningTopVertexOut {
    float4 position [[position]];
    float3 viewPosition;
    float3 modelPosition;
    float3 modelNormal;
};

vertex SpinningTopVertexOut agentSpinningTopVertex(
    uint vertexID [[vertex_id]],
    const device float *vertices [[buffer(0)]],
    constant SpinningTopUniforms &u [[buffer(1)]]
) {
    float3 position = float3(vertices[vertexID * 6], vertices[vertexID * 6 + 1], vertices[vertexID * 6 + 2]);
    float3 normal = float3(vertices[vertexID * 6 + 3], vertices[vertexID * 6 + 4], vertices[vertexID * 6 + 5]);
    float3 viewPosition = (u.rotation * float4(position, 1.0)).xyz;
    float2 pixel = u.placement.xy + viewPosition.xy * u.placement.z;
    float2 size = float2(u.parameters.x, u.placement.w);
    SpinningTopVertexOut out;
    // The top takes the nearer half of the depth range and its reflection the farther, so the top always draws over
    // its reflection, each hiding its own far side
    float depth = 0.5 - viewPosition.z * 0.25;
    out.position = float4(pixel / size * 2.0 - 1.0, u.effects.w > 0.0 ? 0.5 + 0.5 * depth : 0.5 * depth, 1.0);
    out.viewPosition = viewPosition;
    out.modelPosition = position;
    out.modelNormal = normal;
    return out;
}

static float3 spinningTopGradient(float t) {
    float3 c0 = float3(0.0, 0.533, 1.0);
    float3 c1 = float3(0.0, 0.745, 1.0);
    float3 c2 = float3(0.714, 0.337, 1.0);
    return t < 0.476 ? mix(c0, c1, t / 0.476) : mix(c1, c2, (t - 0.476) / 0.524);
}

// The thin film's colours, cyclic in `t`: cyan, blue, violet and a short touch of pink, each blended into the next
static float3 spinningTopFilm(float t) {
    float3 cyan = float3(0.0, 0.86, 1.0);
    float3 blue = float3(0.10, 0.45, 1.0);
    float3 violet = float3(0.58, 0.36, 1.0);
    float3 pink = float3(0.98, 0.50, 0.92);
    t = fract(t);
    if (t < 0.30) { return mix(cyan, blue, smoothstep(0.0, 0.30, t)); }
    if (t < 0.60) { return mix(blue, violet, smoothstep(0.30, 0.60, t)); }
    if (t < 0.75) { return mix(violet, pink, smoothstep(0.60, 0.75, t)); }
    return mix(pink, cyan, smoothstep(0.75, 1.0, t));
}

// How much of its contrast a pattern of `k` cycles per turn keeps, averaged over a sweep of `delta` radians as the
// body turns during an exposure: 1 when nothing blurs
static float spinningTopSweepKeeps(float k, float delta) {
    float x = 0.5 * k * delta;
    return x < 1e-4 ? 1.0 : sin(x) / x;
}

// The reflection in the ground fades with height, strongest at the point and gone by the rim; the top itself is whole
static float4 spinningTopReflected(float4 color, float reflectionOpacity, float height) {
    return reflectionOpacity > 0.0 ? color * reflectionOpacity * exp(-5.0 * max(height, 0.0)) : color;
}

static float3 spinningTopStudio(float3 d) {
    // A broad soft window above and a cool fill below, as a matte surface blurs them.
    float window = smoothstep(0.2, 0.95, d.y) * (0.55 + 0.45 * smoothstep(-0.7, 0.5, -d.x));
    float fill = smoothstep(-0.1, -0.9, d.y) * 0.2;
    return float3(1.0) * window + float3(0.55, 0.75, 1.0) * fill;
}

// The content behind the top seen through frosted glass: a disc of samples around `position`, in drawable pixels,
// spread by `radius` pixels on a golden-angle spiral.
static float3 spinningTopFrosted(
    texture2d<float> backdrop,
    sampler backdropSampler,
    float4 rect,
    float2 position,
    float radius,
    bool isDark
) {
    constexpr int taps = 10;
    float3 sum = float3(0.0);
    for (int i = 0; i < taps; i++) {
        float r = radius * sqrt((float(i) + 0.5) / float(taps));
        float a = float(i) * 2.39996;
        float2 uv = (position + r * float2(cos(a), sin(a)) - rect.xy) / rect.zw;
        float4 sampled = backdrop.sample(backdropSampler, uv);
        sum += sampled.rgb + (1.0 - sampled.a) * (isDark ? 0.0 : 1.0);
    }
    return sum / float(taps);
}

// A hollow top of frosted glass with a coloured coating sprayed on: thin where the shell faces the viewer, so the
// content behind shows through blurred and tinted, dense where the shell turns away, and soft, matte highlights.
// The back wall draws first, the front over it.
fragment float4 agentSpinningTopFragment(
    SpinningTopVertexOut in [[stage_in]],
    bool isFrontFacing [[front_facing]],
    constant SpinningTopUniforms &u [[buffer(0)]],
    texture2d<float> backdrop [[texture(0)]],
    sampler backdropSampler [[sampler(0)]]
) {
    float strength = saturate(u.parameters.y);
    bool isDark = u.parameters.z > 0.5;
    bool hasBackdrop = u.parameters.w > 0.5;

    // A smooth shell without facets. Soft twisted bands in the coating turn with the body and show the spin; they
    // fade out toward the thin stem and the point, where they would flicker.
    float3 modelNormal = normalize(in.modelNormal);
    float radial = length(in.modelPosition.xz);
    float azimuth = atan2(in.modelPosition.z, in.modelPosition.x);
    float swirl = sin(2.0 * azimuth + in.modelPosition.y * 4.0) * smoothstep(0.08, 0.3, radial)
        * spinningTopSweepKeeps(2.0, u.effects.y);

    float3 outward = normalize((u.rotation * float4(modelNormal, 0.0)).xyz);
    // The side of the shell that faces the viewer: the outside of the front wall, the inside of the back wall.
    float3 n = isFrontFacing ? outward : -outward;
    float3 v = float3(0.0, 0.0, 1.0);
    float ndv = saturate(n.z);
    float grazing = 1.0 - ndv;
    float fresnel = pow(grazing, 2.2);

    float2 fromCentre = in.viewPosition.xy - u.material.zw;
    float t = saturate(dot(fromCentre, float2(0.96, -0.27)) * 0.55 + 0.5 + 0.07 * swirl);
    float3 base = spinningTopGradient(t);
    // The coating is a little uneven, as sprayed on.
    float coatDensity = 1.0 + 0.12 * swirl;

    // A thin film over the coating, shifting through its colours as the top turns and toward the silhouette
    float iridescence = saturate(u.effects.x);
    float sweep = u.effects.y;
    float thickness = 0.45
        + 0.22 * sin(azimuth + 3.0 * in.modelPosition.y) * spinningTopSweepKeeps(1.0, sweep)
        + 0.12 * sin(3.0 * azimuth - 5.0 * in.modelPosition.y) * spinningTopSweepKeeps(3.0, sweep);
    float3 film = spinningTopFilm(thickness + 0.55 * grazing);

    float3 light = normalize(float3(-0.45, 0.75, 0.5));
    float diffuse = 0.7 + 0.3 * saturate(dot(n, light));
    float nh = saturate(dot(n, normalize(light + v)));
    // Frosted glass scatters its highlights: wide and soft, no sharp glint.
    float sheen = (pow(nh, 10.0) * 0.16 + pow(nh, 36.0) * 0.12) * (1.0 + u.material.x);

    // The content behind, frosted and bent a little where the thin shell turns away, magnified a little more while
    // held. The lens centres on the box, the model's origin being its point.
    float2 origin = float2(u.placement.x, u.placement.w - u.placement.y);
    float2 centre = origin + float2(u.material.z, -u.material.w) * u.placement.z;
    float lens = mix(0.4, 1.0, strength);
    float2 local = in.position.xy - centre;
    float2 bend = float2(-outward.x, outward.y) * u.placement.z * 0.28 * grazing * grazing * lens;
    float2 samplePosition = centre + local * (1.0 - 0.13 * lens) + bend;
    float frost = u.placement.z * mix(0.034, 0.022, strength);

    if (!isFrontFacing) {
        // The back wall, seen through the hollow: the frosted content behind, tinted by the coating it passes, which
        // gathers where the wall turns away.
        float wall = mix(isDark ? 0.2 : 0.16, 0.55, fresnel) * coatDensity * mix(1.0, 0.7, strength);
        float3 wallColor = mix(base * (isDark ? 0.78 : 0.9), film, 0.35 * iridescence * fresnel);
        if (!hasBackdrop) {
            float opacity = max(wall, u.material.y * 0.5);
            return spinningTopReflected(float4(wallColor * opacity, opacity), u.effects.w, in.modelPosition.y);
        }
        float3 behind = spinningTopFrosted(backdrop, backdropSampler, u.backdrop, samplePosition, frost, isDark);
        // Light that crosses the coloured shell takes its colour, and the frosting adds a milky veil.
        float3 transmitted = behind * mix(float3(1.0), base, 0.55);
        transmitted = mix(transmitted, float3(isDark ? 0.75 : 1.0), isDark ? 0.05 : 0.1);
        return spinningTopReflected(float4(mix(transmitted, wallColor, wall), 1.0), u.effects.w, in.modelPosition.y);
    }

    // The front wall: a thin coloured coat over the hollow, denser toward the silhouette, with the matte sheen and a
    // soft rim where the frosted surface scatters the light around it.
    float3 coat = mix(base * diffuse, film, iridescence * (0.18 + 0.5 * fresnel));
    coat += spinningTopStudio(reflect(-v, n)) * (0.06 + 0.22 * fresnel);
    coat = mix(coat, float3(1.0), fresnel * (isDark ? 0.18 : 0.24));
    float3 sheenColor = mix(float3(1.0), film, 0.7 * iridescence);
    // A fast spin smears the surface into fine rings around the body
    float rings = pow(0.5 + 0.5 * sin(46.0 * in.modelPosition.y + 1.7 * sin(13.0 * in.modelPosition.y)), 6.0)
        * smoothstep(0.08, 0.3, radial) * saturate(u.effects.z);
    coat = saturate(coat + sheenColor * sheen * (1.0 + 0.8 * iridescence) + 0.35 * rings);
    float coverage = mix(mix(isDark ? 0.34 : 0.3, 0.16, strength), 0.82, smoothstep(0.05, 0.95, grazing));
    float opacity = saturate(coverage * coatDensity + sheen + 0.12 * rings);
    opacity = max(opacity, u.material.y);
    float4 color = float4(coat * opacity, opacity);
    // A rim light along the silhouette in the film's colours: added light on dark, a tint on light, where added light
    // wouldn't show
    float rim = pow(grazing, 3.5) * iridescence;
    if (isDark) {
        color.rgb += film * rim * 0.9;
    } else {
        color.rgb = mix(color.rgb, film * color.a, saturate(0.8 * rim));
    }
    return spinningTopReflected(color, u.effects.w, in.modelPosition.y);
}

// The ground under a large top, in the plane through its point: a contact spot under the point and a soft shadow of the
// body under its rim, which follows the lean. On dark, where a shadow can't darken anything, it pools faint light.
// Matches `SpinningTopRenderer.GroundUniforms`: one float4x4 and four float4, 128 bytes.
struct SpinningTopGroundUniforms {
    float4x4 camera;    // The camera alone, model to view
    float4 placement;   // As the top's: xy: the point in drawable pixels, y up; z: pixels per model unit; w: drawable height
    float4 parameters;  // x: drawable width; yz: the ground point under the rim's centre, model x and z
    float4 shadow;      // x: the contact spot's strength; y: the body's; z: the body's radius, model units; w: a glow
    float4 color;       // rgb: the shadow's or the glow's colour
};

struct SpinningTopGroundOut {
    float4 position [[position]];
    float2 ground;
};

vertex SpinningTopGroundOut agentSpinningTopGroundVertex(
    uint vertexID [[vertex_id]],
    constant SpinningTopGroundUniforms &u [[buffer(1)]]
) {
    float2 corners[4] = { float2(-1.6, -1.6), float2(1.6, -1.6), float2(-1.6, 1.6), float2(1.6, 1.6) };
    float2 ground = corners[vertexID];
    float3 viewPosition = (u.camera * float4(ground.x, 0.0, ground.y, 1.0)).xyz;
    float2 pixel = u.placement.xy + viewPosition.xy * u.placement.z;
    float2 size = float2(u.parameters.x, u.placement.w);
    SpinningTopGroundOut out;
    out.position = float4(pixel / size * 2.0 - 1.0, 0.999, 1.0);
    out.ground = ground;
    return out;
}

fragment float4 agentSpinningTopGroundFragment(
    SpinningTopGroundOut in [[stage_in]],
    constant SpinningTopGroundUniforms &u [[buffer(0)]]
) {
    float2 p = in.ground;
    float contact = exp(-dot(p, p) / (2.0 * 0.045 * 0.045));
    float2 fromBody = p - u.parameters.yz;
    float body = exp(-dot(fromBody, fromBody) / (2.0 * u.shadow.z * u.shadow.z));
    float amount = saturate(u.shadow.x * contact + u.shadow.y * body);
    // Premultiplied: a shadow darkens what is behind, a glow adds light to it
    return u.shadow.w > 0.5 ? float4(u.color.rgb * amount, 0.0) : float4(u.color.rgb * amount, amount);
}
