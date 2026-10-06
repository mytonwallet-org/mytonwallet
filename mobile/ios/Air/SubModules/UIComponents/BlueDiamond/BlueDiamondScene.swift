import Metal
import simd
import Foundation
import WalletContext

private let log = Log("BlueDiamond")

@MainActor
final class BlueDiamondScene {
    struct Uniforms {
        var model: simd_float4x4
        var projection: simd_float4x4
        var inverseModel: simd_float4x4
        var parameters: SIMD4<Float>
        var viewport: SIMD4<Float>
        var sparkleShape: SIMD4<Float>
        var sparkleHalo: SIMD4<Float>
        var crownGradient: SIMD4<Float>
        var pavilionGradient: SIMD4<Float>
        var lightSweep: SIMD4<Float>
        var facetProjection: SIMD4<Float>
        var crownSweep: SIMD4<Float>
        var rightCrownSweep: SIMD4<Float>
        var leftCrownSweep: SIMD4<Float>
        var pavilionSweep: SIMD4<Float>
        var rightPavilionSweep: SIMD4<Float>
        var leftPavilionSweep: SIMD4<Float>
        var appearance = SIMD4<Float>.zero
        var referenceCrownFlash = SIMD4<Float>.zero
        var referencePavilionFlash = SIMD4<Float>.zero
    }

    struct Mesh {
        let buffer: MTLBuffer
        let count: Int
    }

    static let shared: BlueDiamondScene? = {
        do {
            return try BlueDiamondScene()
        } catch {
            log.error("Unable to load diamond: \(error, .public)")
            return nil
        }
    }()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let sampleCount: Int
    let diamondPipeline: MTLRenderPipelineState
    let sparklePipeline: MTLRenderPipelineState
    let depth: MTLDepthStencilState
    let noDepth: MTLDepthStencilState
    let diamond: Mesh
    let mainSparkle: Mesh
    let smallSparkles: Mesh
    let planes: MTLBuffer
    let anchors: MTLBuffer
    private let frames: [Float]
    private let widths: [Float]
    private let camera: [Float]
    private let facetProjection: SIMD4<Float>
    private let projection: simd_float4x4

    private enum ResourceError: Error { case unavailable, invalidModel }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ResourceError.unavailable
        }
        self.device = device
        self.queue = queue
        let sampleCount = [4, 2, 1].first(where: device.supportsTextureSampleCount) ?? 1
        self.sampleCount = sampleCount
        let library = try device.makeDefaultLibrary(bundle: .module)
        func pipeline(vertex: String, fragment: String, blends: Bool) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.rasterSampleCount = sampleCount
            let color = descriptor.colorAttachments[0]!
            // The authored shader already outputs display-space colors.
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = blends
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        diamondPipeline = try pipeline(vertex: "blueDiamondVertex", fragment: "blueDiamondFragment", blends: false)
        sparklePipeline = try pipeline(vertex: "blueDiamondSparkleVertex", fragment: "blueDiamondSparkleFragment", blends: true)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { throw ResourceError.unavailable }
        self.depth = depth
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let noDepth = device.makeDepthStencilState(descriptor: depthDescriptor) else { throw ResourceError.unavailable }
        self.noDepth = noDepth

        func floats(_ name: String, count: Int) throws -> [Float] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "BlueDiamond/models") else {
                throw ResourceError.unavailable
            }
            let data = try Data(contentsOf: url)
            guard data.count == count * 4 else { throw ResourceError.invalidModel }
            return data.withUnsafeBytes { bytes in
                (0..<count).map { Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
            }
        }
        func buffer(_ values: [Float]) throws -> MTLBuffer {
            guard let result = device.makeBuffer(bytes: values, length: values.count * 4, options: .storageModeShared) else {
                throw ResourceError.unavailable
            }
            return result
        }
        func mesh(_ name: String, count: Int, components: Int) throws -> Mesh {
            try Mesh(buffer: buffer(floats(name, count: count * components)), count: count)
        }
        diamond = try mesh("vertices", count: 4968, components: 12)
        mainSparkle = try mesh("main", count: 1344, components: 8)
        smallSparkles = try mesh("small", count: 384, components: 8)
        planes = try buffer(floats("planes", count: 17 * 4))
        anchors = try buffer(floats("anchors", count: 8 * 8))
        frames = try floats("frames", count: 1441 * 42)
        widths = try floats("widths", count: 91)
        camera = try floats("camera", count: 3)
        let facet = try floats("facetProjection", count: 4)
        facetProjection = SIMD4(facet[0], facet[1], facet[2], facet[3])
        let scale = 1.52 * widths[0] / 0.9975
        let depthScale = 1 / camera[2]
        let perspective = -depthScale / camera[1]
        let shift = 0.12 / scale
        projection = simd_float4x4(columns: (
            SIMD4(1 / scale, 0, 0, 0), SIMD4(0, 1 / scale, 0, 0),
            SIMD4(0, shift * perspective, -depthScale / 6, perspective),
            SIMD4(0, shift * depthScale, 0.5 * depthScale, depthScale)
        ))
    }

    func uniforms(size: CGSize, time: Float, yaw: Float, pitch: Float, speed: Float, scale: Float) -> Uniforms {
        let position = (time * 240).truncatingRemainder(dividingBy: 1440)
        let index = Int(position)
        let fraction = position - Float(index)
        func value(_ offset: Int) -> Float {
            let from = frames[index * 42 + offset]
            return from + (frames[(index + 1) * 42 + offset] - from) * fraction
        }
        func vector(_ offset: Int) -> SIMD4<Float> { SIMD4(value(offset), value(offset + 1), value(offset + 2), value(offset + 3)) }
        let tilt = pitch + camera[0]
        let s = sin(tilt), c = cos(tilt), sy = sin(yaw), cy = cos(yaw)
        let model = simd_float4x4(columns: (
            SIMD4(cy, s * sy, -c * sy, 0), SIMD4(0, c, s, 0),
            SIMD4(sy, -s * cy, c * cy, 0), SIMD4(0, 0, 0, 1)
        ))
        let widthScale = widthScale(yaw: yaw, tilt: tilt)
        var projection = projection
        projection[0][0] *= widthScale
        for column in 0..<4 {
            projection[column][0] *= scale
            projection[column][1] *= scale
        }
        var anchor: Float = 0
        var maxFacing: Float = -1
        for i in 0..<4 {
            let angle = Float(i) * .pi / 2
            let facing = cos(pitch) * cos(yaw + angle)
            if facing > maxFacing { maxFacing = facing; anchor = angle }
        }
        let facing = max(0, min(1, 1 - acos(max(-1, min(1, maxFacing))) / (.pi / 15)))
        let calm = max(0, min(1, (.pi * (2 / 15) / max(speed, 0.001) - 0.06) / 0.34))
        return Uniforms(model: model, projection: projection, inverseModel: model.transpose,
            parameters: SIMD4(time, 0.72, 1, 1), viewport: SIMD4(Float(size.width), Float(size.height), 17, 0),
            sparkleShape: vector(36), sparkleHalo: SIMD4(value(40), anchor, widthScale, Self.smooth(calm) * Self.smooth(facing)),
            crownGradient: vector(0), pavilionGradient: vector(4), lightSweep: vector(8), facetProjection: facetProjection,
            crownSweep: vector(12), rightCrownSweep: vector(16), leftCrownSweep: vector(20),
            pavilionSweep: vector(24), rightPavilionSweep: vector(28), leftPavilionSweep: vector(32))
    }

    private func widthScale(yaw: Float, tilt: Float) -> Float {
        let quarterTurn = Float.pi / 2
        let angle = abs(yaw - (yaw / quarterTurn).rounded() * quarterTurn)
        let position = min(90, angle * (360 / .pi))
        let index = min(89, Int(position))
        let t = position - Float(index)
        let from = widths[index], to = widths[index + 1]
        let fromSlope = index == 0 ? 0 : (to - widths[index - 1]) / 2
        let toSlope = index + 2 >= widths.count ? 0 : (widths[index + 2] - from) / 2
        let a = (from - to) * 2 + fromSlope + toSlope
        let b = (to - from) * 3 - fromSlope * 2 - toSlope
        let width = ((a * t + b) * t + fromSlope) * t + from
        let target = (1 - 0.035 * pow(sin(2 * angle), 2)) * widths[0]
        let fade = Self.smooth(max(0, min(1, (abs(sin(tilt)) - sin(0.25)) / (sin(0.96) - sin(0.25)))))
        return 1 + (1 - fade) * (target / width - 1)
    }

    private static func smooth(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
