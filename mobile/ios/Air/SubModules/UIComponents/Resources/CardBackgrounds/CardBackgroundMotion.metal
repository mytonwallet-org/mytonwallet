#include <metal_stdlib>
using namespace metal;

// At time zero every displacement is zero, preserving the original generator artwork.
// The edge envelope fixes the card boundary so the shader never reveals empty pixels.
static float2 cardMotionPosition(float2 position, float2 size, float time, float amount, float seed) {
    if (amount == 0.0) { return position; }
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
    float2 touchPosition;
    float touchOpacity;
    float touchExtent;
    float linearBlur;
    uint experimentalShine;
    float2 surfaceTilt;
    uint customSurface;
    uint starGrowth;
    uint starBlend;
    uint materialEnabled;
    uint materialEnvironment;
    uint materialPreset;
    float materialIntensity;
    float materialBevel;
    float materialEmboss;
    float materialDepth;
    float2 materialTilt;
    float4 starAppearance; // inside/outside size, inside/outside opacity
    float2 telegramShape; // angular width and softness
    float4 gramControl; // rotation, balance, behavior mode, v2 energy
    float4 gramLight;
    float4 gramView;
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

// New Gram input models share both shine profiles and the exact star coverage.
// A small anisotropic material approximation: a fixed distant lamp, a perspective
// viewer and a radial brushed face. Half-vector azimuth rotates the reflection;
// incident angle and specular alignment change its energy continuously.
static float2 cardGramReflection(float2 uv, constant CardUniforms &u) {
    if (u.gramControl.z > 3.5) { return float2(u.gramControl.x, clamp(u.gramControl.w, 0.0, 1.0)); }
    if (u.gramControl.z < 2.5) { return float2(u.gramControl.x, 1.0); }
    float2 point = float2(uv.x - 0.5, (0.5 - uv.y) * u.size.y / max(u.size.x, 1.0));
    float3 light = u.gramLight.xyz / max(length(u.gramLight.xyz), 0.0001);
    float3 eye = u.gramView.xyz - float3(point * 0.35, 0);
    float3 view = eye / max(length(eye), 0.0001);
    float3 halfSum = light + view;
    float3 halfway = halfSum / max(length(halfSum), 0.0001);
    float radius = length(halfway.xy);
    float rotation = radius > 0.00001 ? atan2(halfway.y, halfway.x) - atan2(0.5, -0.35) : 0;
    // Fade through a head-on light where the angular direction is undefined.
    float energy = pow(max(halfway.z, 0.0), 8.0) * max(light.z, 0.0) / 0.78;
    energy *= smoothstep(0.0, 0.045, radius) * smoothstep(0.0, 0.15, view.z);
    return float2(rotation, clamp(energy, 0.0, 1.4));
}

// Adapted from Telegram-iOS WalletCardBackground.metal, commit
// f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838 (see TELEGRAM_SHINE_SOURCE.json).
// Keep Telegram's core/halo wedges, quintic center fade, lobe balance and cyan
// linear-light contribution. The lab supplies its existing continuous input and
// exposes width/softness; the original artwork, stars and materials remain separate.
static float cardTelegramLightField(float2 uv, constant CardUniforms &u) {
    float aspect = u.size.y / max(u.size.x, 1.0);
    float2 position = float2((uv.x - 0.5) * 2.0, (0.5 - uv.y) * 2.0 * aspect);
    float radius = length(position);
    float2 radial = radius > 0.0001 ? position / radius : float2(1.0, 0.0);
    float2 tangent = float2(-radial.y, radial.x);
    float2 idleDirection = normalize(float2(1.0, -aspect));
    float2 perpendicular = float2(-idleDirection.y, idleDirection.x);
    // CardSurfaceLight already carries normalized and smoothed screen tilt.
    // Convert UIKit's downward Y into the material's upward Y.
    float2 tiltDirection = float2(-u.tilt.x, u.tilt.y);
    float turn = clamp(dot(tiltDirection, perpendicular) / max(abs(perpendicular.y), 0.0001), -1.0, 1.0);
    float2 control = cardGramReflection(uv, u);
    float angle = u.gramControl.z > 0.5 ? control.x : turn * M_PI_F / 2.0;
    float c = cos(angle), s = sin(angle);
    float2 keyDirection = float2(idleDirection.x * c - idleDirection.y * s,
                                idleDirection.x * s + idleDirection.y * c);
    float alignment = dot(tangent, keyDirection);
    // At 120 degrees / 18pt, use Telegram's roughness 0.20 profile exactly.
    float widthScale = clamp(u.telegramShape.x, 30.0, 180.0) / 120.0;
    float blur = clamp(u.telegramShape.y, 0.0, 180.0);
    float baseWidth = mix(0.30, 0.44, (0.20 - 0.13) / 0.17) * widthScale;
    float extraBlur = max(0.0, blur - 18.0) / 180.0;
    float wedgeWidth = sqrt(baseWidth * baseWidth + extraBlur * extraBlur);
    float core = exp(-alignment * alignment / max(2.0 * wedgeWidth * wedgeWidth, 0.0001));
    float haloWidth = wedgeWidth * 1.70;
    float halo = exp(-alignment * alignment / max(2.0 * haloWidth * haloWidth, 0.0001));
    float progress = clamp(radius / 0.275, 0.0, 1.0);
    float curve = progress * progress * progress * (progress * (progress * 6.0 - 15.0) + 10.0);
    float centerFade = mix(0.10, 1.0, curve);
    float haloAmount = mix(0.0, 0.42, min(1.0, blur / 18.0));
    float field = mix(core, halo, haloAmount) * centerFade;
    float lobeBalance = mix(0.72, 1.0, 0.5 + 0.5 * dot(radial, keyDirection));
    // Regularize only the subpixel center, avoiding a directional pinprick.
    float centerAA = smoothstep(0.0, 2.0 / max(u.size.x, 1.0), radius);
    float balance = u.gramControl.z > 1.5 && u.gramControl.z < 2.5
        ? 1.0 + 0.65 * clamp(u.gramControl.y, -1.0, 1.0) * dot(radial, keyDirection) : 1.0;
    return mix(0.086, field * lobeBalance * balance, centerAA) * baseWidth / wedgeWidth * control.y;
}

static float cardLightField(float2 uv, constant CardUniforms &u, texture2d<float> light) {
    if (u.shine <= 0) { return 0; }
    if (u.shineStyle == 3) { return cardTelegramLightField(uv, u); }
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
        // Exact convolution of the original Gaussian band with Gaussian blur.
        // Preserve its total light; zero blur is the original shader response.
        float sigma = max(0.0, u.linearBlur) * u.size.x / 400.0;
        float softWidth = sqrt(width * width + 5.5451774 * sigma * sigma);
        // Include the Gaussian tail so either endpoint clears every card corner.
        float travel = dot(abs(normal), u.size) * 0.5 + softWidth * 1.5;
        float distance = (dot(point, normal) - u.tilt.y * travel) / softWidth;
        float blurred = (width / softWidth) * exp(-2.7725887 * distance * distance);
        // Below the original softness, approach a crisp band with a pixel-wide
        // antialiased edge. Original (0) and existing saved positive values retain
        // their exact response; the new upper limit allows much stronger blur.
        // This helper is shared by fragment and star vertex shaders, so use a
        // half-point edge width rather than fragment-only screen derivatives.
        float edge = max(0.5 / softWidth, 0.001);
        float crisp = 1.0 - smoothstep(0.5 - edge, 0.5 + edge, abs(distance));
        return mix(blurred, crisp, clamp(-u.linearBlur / 40.0, 0.0, 1.0));
    }
    constexpr sampler sampleLight(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 control = cardGramReflection(uv, u);
    float direction = u.gramControl.z > 0.5 ? -control.x : u.tilt.x * M_PI_F / 2 + u.tilt.y * M_PI_F / 3;
    float angle = -M_PI_F / 2 + direction;
    float c = cos(angle), s = sin(angle);
    float2 local = float2(c * point.x + s * point.y, -s * point.x + c * point.y) / u.size.x;
    float balance = 1.0;
    if (u.gramControl.z > 1.5 && u.gramControl.z < 2.5) {
        float2 axis = float2(cos(angle - M_PI_F / 5), sin(angle - M_PI_F / 5));
        balance += 0.65 * clamp(u.gramControl.y, -1.0, 1.0) * dot(point / max(length(point), 0.001), axis);
    }
    return light.sample(sampleLight, local / 1.5 + 0.5).a * balance * control.y;
}

// Facet boundaries traced from HomeCard.pdf, 370 x 215 PDF points.
// These are its four overlaid trapezoids (objects 13/23/33/43), not a new mesh.
// Assigned face slopes approximate a shallow cut-glass laminate; the PDF has no 3D normals.
struct CardCrystalSurface {
    float3 normal;
    float roughness;
    float edge;
};

static CardCrystalSurface cardCrystalSurface(float2 uv) {
    float2 p = uv * float2(370, 215);
    float y = uv.y;
    float outerLeft = -60 + 61.250004 * y;
    float outerRight = 430.000031 - 61.250031 * y;
    float innerLeft = 1 + 61.333332 * y;
    float innerRight = 369 - 61.333344 * y;
    float wingLeft = 62.000008 + 61.499996 * y;
    float wingRight = 307 - 61 * y;
    // Fragment derivatives keep the exact vector edges smooth at every card size/tilt.
    float aa = max(fwidth(p.x) + 0.3 * fwidth(p.y), 0.25);
    float outer = smoothstep(-aa, aa, min(p.x - outerLeft, outerRight - p.x));
    float inner = smoothstep(-aa, aa, min(p.x - innerLeft, innerRight - p.x));
    float leftWing = smoothstep(-aa, aa, min(p.x - wingLeft, 185 - p.x));
    float rightWing = smoothstep(-aa, aa, min(p.x - 185, wingRight - p.x));
    float side = mix(-1.0, 1.0, smoothstep(185 - aa, 185 + aa, p.x));
    float2 slope = float2(side * 0.32, 0.12);
    slope = mix(slope, float2(-side * 0.18, -0.10), outer);
    slope = mix(slope, float2(side * 0.12, 0.14), inner);
    slope = mix(slope, float2(0.29, -0.09), leftWing);
    slope = mix(slope, float2(-0.26, 0.07), rightWing);
    float edgeDistance = min(min(abs(p.x - innerLeft), abs(p.x - innerRight)),
                            min(min(abs(p.x - wingLeft), abs(p.x - wingRight)), abs(p.x - 185)));
    return { normalize(float3(slope, 1)), mix(0.32, 0.18, max(leftWing, rightWing)),
             exp(-edgeDistance / max(0.7, aa)) };
}

static float3 cardCrystalArtwork(float2 uv, texture2d<float> artwork, constant CardUniforms &u) {
    constexpr sampler materialSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 position = cardMotionPosition(uv * u.size, u.size, u.time, u.strength, u.seed);
    return artwork.sample(materialSampler, position / max(u.size, float2(1))).rgb;
}

static float3 cardCrystalReflection(float2 uv, float3 srgb, float3 base,
                                    texture2d<float> artwork, constant CardUniforms &u) {
    CardCrystalSurface surface = cardCrystalSurface(uv);
    if (u.customSurface != 0) {
        // Custom cards have their own artwork, not the blue card's trapezoids.
        // A shallow embossed approximation follows the original printed texture.
        float2 step = float2(1.0 / 400, 1.0 / 232);
        float3 weights = float3(0.2126, 0.7152, 0.0722);
        float dx = dot(cardCrystalArtwork(uv + float2(step.x, 0), artwork, u)
                     - cardCrystalArtwork(uv - float2(step.x, 0), artwork, u), weights);
        float dy = dot(cardCrystalArtwork(uv + float2(0, step.y), artwork, u)
                     - cardCrystalArtwork(uv - float2(0, step.y), artwork, u), weights);
        surface = { normalize(float3(clamp(float2(-dx, -dy) * 1.8, -0.12, 0.12), 1)), 0.45, 0 };
    }
    float2 point = (uv - 0.5) * u.size;
    float3 view = normalize(float3(-point / u.size.x * 0.35 + u.surfaceTilt * 0.22, 1.6));
    float3 reflection = reflect(-view, surface.normal);
    float3 flatReflection = reflect(-view, float3(0, 0, 1));
    float2 bandNormal = float2(sin(u.linearAngle), cos(u.linearAngle));
    float width = u.size.x * max(u.linearWidth, 0.02);
    float sigma = max(0.0, u.linearBlur) * u.size.x / 400;
    // Preserve the original sweep endpoints; move the environment reflection per face.
    float travel = dot(abs(bandNormal), u.size) * 0.5 + sqrt(width * width + 5.5451774 * sigma * sigma) * 1.5;
    float distance = dot(point, bandNormal) - u.tilt.y * travel
        + dot(reflection.xy - flatReflection.xy, bandNormal) * u.size.x * 0.42;
    float facetWidth = width * (0.30 + surface.roughness * 0.65)
        * mix(1.0, 0.46, saturate(-u.linearBlur / 40));
    float softWidth = sqrt(facetWidth * facetWidth + 5.5451774 * sigma * sigma);
    // Slight dispersion separates wavelengths only within the moving highlight.
    float dispersion = u.size.x * 0.006 * (1 - surface.normal.z + 0.12);
    float3 d = (distance + float3(-dispersion, 0, dispersion)) / softWidth;
    float3 lobe = exp(-2.7725887 * d * d) * (facetWidth / softWidth);
    float ndv = saturate(dot(surface.normal, view));
    float fresnel = 0.04 + 0.96 * pow(1 - ndv, 5.0);
    float energy = max(lobe.r, max(lobe.g, lobe.b));

    // A shallow refracting layer bends only the artwork; card text stays crisp above it.
    float2 flatRay = refract(-view, float3(0, 0, 1), 1.0 / 1.48).xy;
    float2 aspect = float2(1, u.size.x / max(1.0, u.size.y));
    float2 redUV = uv + (refract(-view, surface.normal, 1.0 / 1.46).xy - flatRay) * 0.055 * aspect;
    float2 greenUV = uv + (refract(-view, surface.normal, 1.0 / 1.48).xy - flatRay) * 0.055 * aspect;
    float2 blueUV = uv + (refract(-view, surface.normal, 1.0 / 1.50).xy - flatRay) * 0.055 * aspect;
    float3 transmitted = float3(cardCrystalArtwork(redUV, artwork, u).r,
                                 cardCrystalArtwork(greenUV, artwork, u).g,
                                 cardCrystalArtwork(blueUV, artwork, u).b);
    srgb += (cardSRGB(transmitted) - cardSRGB(base)) * energy * saturate(u.shine * 5);
    float3 radiance = lobe * float3(0.90, 0.97, 1.0) * (2.3 + fresnel * 4)
        + energy * surface.edge * float3(0.30, 0.46, 0.58);
    // Screen-like energy compression avoids clipped white stripes on bright blue facets.
    return 1 - (1 - saturate(srgb)) * exp(-radiance * u.shine);
}

vertex CardVertex cardBackgroundVertex(uint id [[vertex_id]]) {
    const float2 positions[] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    float2 p = positions[id];
    return { float4(p, 0, 1), float2((p.x + 1) * 0.5, (1 - p.y) * 0.5) };
}

// Procedural studio environment and shallow relief derived from the actual print.
// This is an artistic material model, not a scanned physical surface.
static float3 cardMaterial(float2 uv, float3 base, texture2d<float> artwork, constant CardUniforms &u) {
    float2 step = float2(1.0/400, 1.0/232);
    float3 weights = float3(0.2126, 0.7152, 0.0722);
    float dx = dot(cardCrystalArtwork(uv + float2(step.x,0), artwork,u) - cardCrystalArtwork(uv - float2(step.x,0),artwork,u),weights);
    float dy = dot(cardCrystalArtwork(uv + float2(0,step.y), artwork,u) - cardCrystalArtwork(uv - float2(0,step.y),artwork,u),weights);
    CardCrystalSurface crystal = cardCrystalSurface(uv);
    float2 slope = (u.customSurface == 0 && u.shineStyle == 0) ? crystal.normal.xy * 0.65 : float2(0);
    slope += clamp(float2(-dx,-dy) * (1.5 + u.materialEmboss * 8), -0.35, 0.35);
    float3 normal = normalize(float3(slope, 1));
    float3 view = normalize(float3(u.materialTilt * 0.65 - (uv-0.5)*float2(0.3,0.18), 1.4));
    float3 reflection = reflect(-view, normal);
    float2 r = reflection.xy;
    float roughness = u.materialPreset == 0 ? 0.28 : (u.materialPreset == 1 ? 0.055 : 0.14);
    float3 a = float3(0.78,0.89,1.0), b = float3(1.0,0.94,0.83), c = float3(0.62,0.79,1.0);
    if (u.materialEnvironment == 1) { a=float3(1,0.59,0.24); b=float3(1,0.83,0.52); c=float3(0.60,0.32,0.48); }
    if (u.materialEnvironment == 2) { a=float3(0.18,0.93,1); b=float3(1,0.18,0.67); c=float3(0.48,0.27,1); }
    float2 q1 = (r-float2(-0.25,0.24))/float2(roughness,0.55);
    float2 q2 = (r-float2(0.34,-0.12))/float2(roughness*0.75,0.44);
    float2 q3 = (r-float2(-0.04,-0.42))/float2(0.58,roughness);
    float3 radiance = a*exp(-dot(q1,q1)*1.7) + b*exp(-dot(q2,q2)*1.7)*0.75 + c*exp(-dot(q3,q3)*1.7)*0.55;
    if (u.materialPreset == 2) {
        float film = dot(normal,view)*10 + dot(r,float2(3,-2));
        float3 pearl = 0.5 + 0.5*cos(film+float3(0,2.094,4.189));
        radiance = radiance*0.7 + pearl*0.18;
    }
    float fresnel = pow(1-saturate(dot(normal,view)),3);
    float3 result = 1-(1-saturate(base))*exp(-radiance*u.materialIntensity*(0.5+fresnel*2));
    // Thin rounded perimeter and internal facet/print edges, never a full-card wash.
    float2 point = uv*float2(400,232);
    float2 q = abs(point-float2(200,116))-float2(174,90);
    float sdf = length(max(q,0.0))+min(max(q.x,q.y),0.0)-26;
    float edge = exp(-pow((sdf+1.2)/0.8,2.0));
    float inner = (u.customSurface == 0 && u.shineStyle == 0) ? crystal.edge : saturate(length(float2(dx,dy))*5);
    float directional = 0.25+0.75*saturate(dot(normalize((uv-0.5)+float2(0.0001)), normalize(u.materialTilt+float2(0.2,-0.6))));
    result += (1-result) * (edge*directional + inner*max(radiance.r,max(radiance.g,radiance.b))*0.4) * u.materialBevel;
    float relief = dot(float2(dx,dy),normalize(u.materialTilt+float2(-0.4,-0.6)))*u.materialEmboss*1.8;
    result += relief*(relief>0 ? 1-result : result);
    return saturate(result);
}

fragment float4 cardBackgroundFragment(CardVertex in [[stage_in]], texture2d<float> artwork [[texture(0)]],
                                      texture2d<float> light [[texture(1)]],
                                      texture2d<float> brush [[texture(2)]],
                                      texture2d<float> firstSpot [[texture(3)]],
                                      texture2d<float> secondSpot [[texture(4)]],
                                      texture2d<float> thirdSpot [[texture(5)]],
                                      texture2d<float> touchSpot [[texture(6)]],
                                      constant CardUniforms &u [[buffer(0)]]) {
    constexpr sampler sampleArtwork(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 materialUV = in.uv;
    if (u.materialEnabled != 0) {
        float envelope = sin(M_PI_F*in.uv.x)*sin(M_PI_F*in.uv.y);
        materialUV += u.materialTilt * u.materialDepth * 0.45 / max(u.size,float2(1)) * envelope;
    }
    float2 position = cardMotionPosition(materialUV * u.size, u.size, u.time, u.strength, u.seed);
    float4 color = artwork.sample(sampleArtwork, position / max(u.size, float2(1)));
    if (u.shine > 0 || u.brush > 0 || u.blobCount > 0 || u.contrastColor >= 0 || u.touchOpacity > 0 || u.materialEnabled != 0) {
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
            if (u.experimentalShine != 0 && u.shineStyle == 0) {
                srgb = cardCrystalReflection(in.uv, srgb, color.rgb, artwork, u);
            } else {
                float field = cardLightField(in.uv, u, light);
                if (u.shineStyle == 3) {
                    float3 linear = select(pow((srgb + 0.055) / 1.055, float3(2.4)), srgb / 12.92, srgb <= 0.04045);
                    // Telegram uses a cyan reflection of 0.32 in linear light.
                    // Map the lab's original opacity0.24 to that reference intensity.
                    constexpr float3 cyanReflection = float3(0.090, 0.565, 0.965);
                    srgb = saturate(cardSRGB(linear + cyanReflection * field * (0.32 / 0.24) * u.shine));
                } else {
                    srgb = saturate(srgb + field * u.shine);
                }
            }
        }
        if (u.touchOpacity > 0 && u.touchExtent > 0) {
            constexpr sampler sampleTouch(coord::normalized, address::clamp_to_zero, filter::linear);
            float2 point = (in.uv - 0.5) * u.size;
            float2 center = u.touchPosition * u.size * 0.5;
            float field = touchSpot.sample(sampleTouch, (point - center) / u.touchExtent + 0.5).a;
            srgb = saturate(srgb + field * u.touchOpacity);
        }
        if (u.materialEnabled != 0) { srgb = cardMaterial(in.uv, srgb, artwork, u); }
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
    float field = cardLightField(uv, u, light);
    float activation = field * min(1.0, u.shine * 5) * (0.35 + 0.65 * u.activity);
    float radius = star.radius * (0.15 + 0.85 * twinkle + 0.45 * activation + 0.1 * u.activity);
    float opacity = saturate(twinkle * 0.65 + activation * 0.7 + u.activity * 0.12);
    if (u.starGrowth != 0) {
        // Spatial membership follows the actual rotating light texture; its
        // brightness/activity must not turn a star inside the beam into an outside star.
        float inside = u.shine > 0 ? smoothstep(0.05, 0.75, field) : 0;
        radius *= mix(clamp(u.starAppearance.y, 0.0, 2.0), clamp(u.starAppearance.x, 0.0, 2.0), inside);
        opacity *= mix(saturate(u.starAppearance.w), saturate(u.starAppearance.z), inside);
    }
    float2 local = corners[id];
    float2 point = (star.position + local * radius) / float2(400, 232);
    return { float4(point.x * 2 - 1, 1 - point.y * 2, 0, 1), local, opacity };
}

fragment float4 cardStarFragment(CardStarVertex in [[stage_in]]) {
    float distance = sqrt(abs(in.local.x)) + sqrt(abs(in.local.y));
    float aa = max(fwidth(distance), 0.02);
    float alpha = (1 - smoothstep(1 - aa, 1 + aa, distance)) * in.opacity;
    return float4(1, 1, 1, alpha);
}

// Sample the completed background in a separate pass: supported on device,
// simulator and Mac without framebuffer-fetch assumptions.
fragment float4 cardCopyFragment(CardVertex in [[stage_in]], texture2d<float> backdrop [[texture(7)]]) {
    return backdrop.read(uint2(in.position.xy));
}
fragment float4 cardStarBlendFragment(CardStarVertex in [[stage_in]], texture2d<float> backdrop [[texture(7)]]) {
    float distance = sqrt(abs(in.local.x)) + sqrt(abs(in.local.y));
    float aa = max(fwidth(distance),0.02);
    float alpha = (1-smoothstep(1-aa,1+aa,distance))*in.opacity;
    float3 base = cardSRGB(backdrop.read(uint2(in.position.xy)).rgb);
    // W3C Soft Light with a white source: D(Cb), then source-alpha blending.
    float3 d = select(sqrt(max(base,0.0)),((16*base-12)*base+4)*base,base<=0.25);
    return float4(select(pow((d+0.055)/1.055,float3(2.4)),d/12.92,d<=0.04045),alpha);
}
