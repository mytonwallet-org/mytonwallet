// Run on a Mac with Metal, from the repository root:
// swift dev/tests/card-background-effects.swift
// Tests the production GPU functions, including their Swift/Metal uniform layout.
import Foundation
import Metal
import simd

struct U {
    var size: SIMD2<Float>
    var time: Float
    var strength: Float
    var seed: Float
    var shine: Float
    var tilt: SIMD2<Float>
    var shineStyle: UInt32 = 1
    var linearWidth: Float = 0.28
    var brush: Float = 0
    var spotPadding: Float = 128
    var blobTime: Float = 0
    var blobCount: UInt32 = 0
    var contrastOpacity: Float = 0
    var contrastColor: Float = -1
    var blobMotion: UInt32 = 1
    var activity: Float = 0
    var linearAngle: Float = 61 * .pi / 180
}
let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let root = "mobile/ios/Air/SubModules/"
let source = try String(
    contentsOfFile: root + "UIComponents/Resources/CardBackgrounds/CardBackgroundMotion.metal",
    encoding: .utf8)
let reference = """
    fragment float4 blobProbe(CardVertex in [[stage_in]], constant CardUniforms &u [[buffer(0)]]) {
        return float4(cardBlobOffset(u.blobTime, u.seed, u.blobCount), 0, 1);
    }
    fragment float4 centerProbe(CardVertex in [[stage_in]], constant CardUniforms &u [[buffer(0)]]) {
        return float4(cardBlobSamplePosition(in.uv, u, 0), 0, 1);
    }
    fragment float4 lightProbe(CardVertex in [[stage_in]], constant CardUniforms &u [[buffer(0)]],
                              texture2d<float> light [[texture(0)]]) {
        return float4(cardLightField(in.uv, u, light));
    }
    """
let library = try device.makeLibrary(source: source + reference, options: nil)
func pipeline(_ name: String) throws -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = library.makeFunction(name: "cardBackgroundVertex")
    d.fragmentFunction = library.makeFunction(name: name)
    d.colorAttachments[0].pixelFormat = .rgba32Float
    return try device.makeRenderPipelineState(descriptor: d)
}
let width = 128
let height = 75
func texture(_ w: Int, _ h: Int, _ pixel: (Int, Int) -> SIMD4<Float>) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
    d.storageMode = .shared
    d.usage = [.shaderRead, .renderTarget]
    let t = device.makeTexture(descriptor: d)!
    let values = (0..<h).flatMap { y in (0..<w).map { x in pixel(x, y) } }
    values.withUnsafeBytes {
        t.replace(
            region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!,
            bytesPerRow: w * 16)
    }
    return t
}
// An asymmetric light texture exposes coordinate inversions and shifts.
let light = texture(128, 128) { x, y in SIMD4(1, 1, 1, Float(x * x + y * 19) / 19000) }
func render(_ p: MTLRenderPipelineState, _ u: U, lightTexture: MTLTexture = light) -> [SIMD4<Float>] {
    var u = u
    let out = texture(width, height) { _, _ in .zero }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = out
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    let c = queue.makeCommandBuffer()!
    let e = c.makeRenderCommandEncoder(descriptor: pass)!
    e.setRenderPipelineState(p)
    e.setFragmentTexture(lightTexture, index: 0)
    e.setFragmentBytes(&u, length: MemoryLayout<U>.stride, index: 0)
    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    e.endEncoding()
    c.commit()
    c.waitUntilCompleted()
    precondition(c.status == .completed)
    var pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
    pixels.withUnsafeMutableBytes {
        out.getBytes(
            $0.baseAddress!, bytesPerRow: width * 16, from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)
    }
    return pixels
}
precondition(MemoryLayout<U>.stride == 80)
let probe = try pipeline("blobProbe")
var probes = 0
for index: UInt32 in 0..<3 {
    for seed: Float in [0, 0.39, 0.93] {
        for t: Float in [0, 0.1, 0.5, 1, 2, 4, 8, 16, 60, 1000] {
            let u = U(
                size: SIMD2(370, 215), time: 0, strength: 15, seed: seed, shine: 0, tilt: .zero,
                blobTime: t, blobCount: index)
            let point = render(probe, u)[0]
            precondition(
                abs(point.x) <= 18 + 3 * Float(index) + 0.0001
                    && abs(point.y) <= 12 + 2 * Float(index) + 0.0001)
            if t == 0 { precondition(point.x == 0 && point.y == 0) }
            precondition(abs(point.x) < u.spotPadding && abs(point.y) < u.spotPadding)
            probes += 1
        }
    }
}
print(
    "PASS \(probes) blob positions: original anchor at zero, bounded orbit, all samples inside texture padding"
)

let centerProbe = try pipeline("centerProbe")
var centerChecks = 0
let idlePeriod: Float = 40 / 0.7
for time: Float in [0, 1, idlePeriod / 4, idlePeriod / 2, idlePeriod * 0.75, idlePeriod, 70, 1000] {
    let u = U(
        size: SIMD2(400, 232), time: 0, strength: 0, seed: 0, shine: 0, tilt: .zero, blobTime: time)
    let points = render(centerProbe, u)
    for y in 0..<height {
        for x in 0..<width {
            let source = SIMD2(
                (Float(x) + 0.5) / Float(width) * 400 - 200,
                (Float(y) + 0.5) / Float(height) * 232 - 116)
            let sample = SIMD2(points[y * width + x].x - 200, points[y * width + x].y - 116)
            precondition(
                abs(simd_length(source) - simd_length(sample)) < 0.001,
                "Rotation must preserve radius in card points")
            precondition(
                sample.x + 200 + 128 > 0 && sample.x + 200 + 128 < 656 && sample.y + 116 + 128 > 0
                    && sample.y + 116 + 128 < 488, "Rotated sample outside padding")
            if time == 0 || time == idlePeriod {
                precondition(
                    simd_length(source - sample) < 0.001, "First/full-turn frames must match")
            }
            if time == idlePeriod / 4 {
                precondition(
                    simd_length(sample - SIMD2(source.y, -source.x)) < 0.001,
                    "Quarter-turn sampling must use inverse rotation")
            }
            centerChecks += 1
        }
    }
}
print(
    "PASS \(centerChecks) GPU center-rotation samples: constant radius, correct quarter-turn direction, seamless full turn, padded coverage"
)

let lightProbe = try pipeline("lightProbe")
func reflection(_ tilt: SIMD2<Float>, size: SIMD2<Float>, shine: Float = 1,
                angle: Float = 61, bandWidth: Float = 0.28) -> [Float] {
    render(lightProbe, U(size: size, time: 0, strength: 0, seed: 0, shine: shine,
                         tilt: tilt, shineStyle: 0, linearWidth: bandWidth, linearAngle: angle * .pi / 180)).map(\.x)
}
func centroid(_ pixels: [Float]) -> SIMD2<Float> {
    var center = SIMD2<Float>.zero
    var total: Float = 0
    for y in 0..<height {
        for x in 0..<width {
            let value = pixels[y * width + x]
            center += SIMD2((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height)) * value
            total += value
        }
    }
    return center / total
}
// Recover the visible ridge from pixels rather than duplicating the shader's math.
func bandAngle(_ pixels: [Float], size: SIMD2<Float>) -> Float {
    var ridge: [SIMD2<Float>] = []
    for y in 0..<height {
        let x = (0..<width).max { pixels[y * width + $0] < pixels[y * width + $1] }!
        if x > 0, x < width - 1, pixels[y * width + x] > 0.995 {
            ridge.append(SIMD2((Float(x) + 0.5) / Float(width) * size.x,
                               (Float(y) + 0.5) / Float(height) * size.y))
        }
    }
    let center = ridge.reduce(.zero, +) / Float(ridge.count)
    let xx = ridge.reduce(Float(0)) { $0 + pow($1.x - center.x, 2) }
    let xy = ridge.reduce(Float(0)) { $0 + ($1.x - center.x) * ($1.y - center.y) }
    return atan2(xy, xx) * 180 / .pi
}
var symmetryChecks = 0
for size: SIMD2<Float> in [SIMD2(300, 174), SIMD2(400, 232), SIMD2(520, 302)] {
    let neutral = reflection(.zero, size: size)
    precondition(simd_distance(centroid(neutral), SIMD2(repeating: 0.5)) < 0.0001,
                 "Mid-sweep shine must cross the card center")
    precondition(abs(bandAngle(neutral, size: size) + 61) < 1,
                 "Reflection must run bottom left to top right at 61 degrees")
    let middleRow = (height / 2) * width
    let halfMaximumColumns = (0..<width).filter { neutral[middleRow + $0] >= 0.5 }.count
    let thickness = Float(halfMaximumColumns) / Float(width) * sin(61 * Float.pi / 180)
    precondition(abs(thickness - 0.28) < 0.01, "Preserve the selected 28% perpendicular band width")
    var previous = SIMD2<Float>(repeating: -1)
    for position: Float in [-0.5, -0.25, 0, 0.25, 0.5] {
        let frame = reflection(SIMD2(0, position), size: size)
        let center = centroid(frame)
        precondition(center.x > previous.x && center.y > previous.y,
                     "Sweep must travel monotonically from top left to bottom right")
        precondition(abs(bandAngle(frame, size: size) + 61) < 1,
                     "Travel must never rotate the diagonal")
        previous = center
        for sideTilt: Float in [-1, -0.4, 0, 0.4, 1] {
            let original = reflection(SIMD2(sideTilt, position), size: size)
            let opposite = reflection(SIMD2(sideTilt, -position), size: size)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    precondition(abs(original[i] - frame[i]) < 0.00001,
                                 "Side tilt must not change the fixed band angle or position")
                    precondition(abs(original[i] - opposite[(height - 1 - y) * width + width - 1 - x]) < 0.00001,
                                 "Sweeps in either direction must cover the same area")
                    symmetryChecks += 1
                }
            }
        }
    }
    for end: Float in [-1, 1] {
        precondition(reflection(SIMD2(0, end), size: size).max()! < 0.003,
                     "Endpoints must clear the whole card, including the Gaussian tail")
    }
    var coverage = [Float](repeating: 0, count: width * height)
    for step in 0...64 {
        let frame = reflection(SIMD2(0, Float(step) / 32 - 1), size: size)
        for i in frame.indices { coverage[i] = max(coverage[i], frame[i]) }
    }
    precondition(coverage.min()! > 0.98, "A full sweep must illuminate every part of the card")
    precondition(reflection(.zero, size: size, shine: 0).allSatisfy { $0 == 0 },
                 "Resting linear shine remains invisible")
}
print("PASS \(symmetryChecks) GPU shine samples: fixed 61-degree band, full-card coverage, symmetric travel, preserved width and invisible endpoints")

for angle: Float in [-85, -61, -30, 15, 30, 61, 70, 85] {
    let size = SIMD2<Float>(400, 232)
    for bandWidth: Float in [0.04, 0.28, 0.6] {
        let middle = reflection(.zero, size: size, angle: angle, bandWidth: bandWidth)
        precondition(abs(bandAngle(middle, size: size) + angle) < 1, "Lab angle must match the rendered band")
        for end: Float in [-1, 1] {
            precondition(reflection(SIMD2(0, end), size: size, angle: angle, bandWidth: bandWidth).max()! < 0.003,
                         "Tuned width and angle must still clear the card at either endpoint")
        }
    }
}
print("PASS tuned linear angles and widths use the production GPU field")

// Sample an analytic circular texture through the production light field. Equal point
// distances must stay circular on wide cards and follow the finger without inversion.
let circle = texture(512, 512) { x, y in
    let distance = hypot((Float(x) + 0.5) / 512 - 0.5, (Float(y) + 0.5) / 512 - 0.5)
    return SIMD4(repeating: max(0, 1 - distance * 2))
}
let circleProbe = try pipeline("lightProbe")
var circleChecks = 0
for size: SIMD2<Float> in [SIMD2(320, 186), SIMD2(400, 232), SIMD2(520, 302)] {
    let extent = size.x * 1.18 + 6 * 28
    for position: SIMD2<Float> in [.zero, SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)] {
        let u = U(size: size, time: 0, strength: 0, seed: 0, shine: 1, tilt: position,
                  shineStyle: 2, linearWidth: extent / size.x)
        let frame = render(circleProbe, u, lightTexture: circle)
        for y in 0..<height {
            for x in 0..<width {
                let point = (SIMD2((Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height)) - 0.5) * size
                let distance = simd_length(point - position * size * 0.5)
                let expected = max(0, 1 - distance * 2 / extent)
                precondition(abs(frame[y * width + x].x - expected) < 0.004,
                             "Touch spot must track the finger in card coordinates and preserve a circular radius")
                circleChecks += 1
            }
        }
    }
}
print("PASS \(circleChecks) GPU touch spot samples: circular geometry, all four corners, correct travel on multiple card widths")

struct Star {
    var position: SIMD2<Float>
    var radius: Float
    var phase: Float
}
let starDescriptor = MTLRenderPipelineDescriptor()
starDescriptor.vertexFunction = library.makeFunction(name: "cardStarVertex")
starDescriptor.fragmentFunction = library.makeFunction(name: "cardStarFragment")
starDescriptor.colorAttachments[0].pixelFormat = .rgba32Float
let starPipeline = try device.makeRenderPipelineState(descriptor: starDescriptor)
func starCoverage(time: Float, activity: Float, shine: Float, tilt: SIMD2<Float>) -> Float {
    var u = U(
        size: SIMD2(400, 232), time: 0, strength: 0, seed: 0, shine: shine, tilt: tilt,
        blobTime: time,
        activity: activity)
    var star = Star(position: SIMD2(280, 50), radius: 10, phase: -.pi / 2)
    let out = texture(width, height) { _, _ in .zero }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = out
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    pass.colorAttachments[0].storeAction = .store
    let command = queue.makeCommandBuffer()!
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(starPipeline)
    encoder.setVertexBytes(&u, length: MemoryLayout<U>.stride, index: 0)
    encoder.setVertexBytes(&star, length: MemoryLayout<Star>.stride, index: 1)
    encoder.setVertexTexture(light, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    precondition(command.status == .completed)
    var pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
    pixels.withUnsafeMutableBytes {
        out.getBytes(
            $0.baseAddress!, bytesPerRow: width * 16, from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)
    }
    return pixels.reduce(0) { $0 + $1.w }
}
let dormant = starCoverage(time: 0, activity: 0, shine: 0, tilt: .zero)
let twinkle = starCoverage(time: 10, activity: 0, shine: 0, tilt: .zero)
let activated = starCoverage(time: 10, activity: 1, shine: 0.2, tilt: .zero)
let left = starCoverage(time: 0, activity: 1, shine: 0.2, tilt: SIMD2(-1, 0))
let right = starCoverage(time: 0, activity: 1, shine: 0.2, tilt: SIMD2(1, 0))
precondition(dormant == 0 && twinkle > 0 && activated > twinkle && abs(left - right) > 0.01)
print(
    "PASS GPU stars: disappear at rest phase, passive twinkle, touch brightening/growth, and spatial shine response (\(dormant), \(twinkle), \(activated), \(left), \(right))"
)
