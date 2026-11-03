import Metal
import simd
import UIKit

/// Draws the spinning top: a hollow shell of frosted glass with a blue-to-purple coating, matte highlights, and the
/// captured content behind it seen through, blurred and tinted, clear toward the middle and denser toward the edge
@MainActor
final class SpinningTopRenderer {
    /// Matches `SpinningTopUniforms` in `AgentSpinningTop.metal`: one `float4x4` and four `float4`, 128 bytes
    struct Uniforms {
        var rotation: simd_float4x4
        /// `x`, `y`: model centre in drawable pixels (y up); `z`: pixels per model unit; `w`: drawable height
        var placement: SIMD4<Float>
        /// `x`: drawable width; `y`: hold strength 0…1; `z`: dark appearance; `w`: has backdrop
        var parameters: SIMD4<Float>
        /// The backdrop's rectangle in drawable pixels (y down): `x`, `y`, width, height
        var backdrop: SIMD4<Float>
        /// `x`: highlight boost; `y`: opacity floor; `zw`: the box centre relative to the model origin, in view units
        var material: SIMD4<Float>
    }

    let device: MTLDevice
    let sampleCount: Int
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let emptyTexture: MTLTexture
    private let sampler: MTLSamplerState

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.device = device
        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunction = library.makeFunction(name: "agentSpinningTopVertex"),
              let fragmentFunction = library.makeFunction(name: "agentSpinningTopFragment") else { return nil }
        let sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        self.sampleCount = sampleCount
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = sampleCount
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.depthState = depthState

        let geometry = SpinningTopGeometry.shared
        var packed: [Float] = []
        packed.reserveCapacity(geometry.vertices.count * 6)
        for vertex in geometry.vertices {
            packed.append(contentsOf: [
                vertex.position.x, vertex.position.y, vertex.position.z,
                vertex.normal.x, vertex.normal.y, vertex.normal.z,
            ])
        }
        guard let vertexBuffer = device.makeBuffer(bytes: packed, length: packed.count * MemoryLayout<Float>.stride),
              let indexBuffer = device.makeBuffer(
                bytes: geometry.indices,
                length: geometry.indices.count * MemoryLayout<UInt32>.stride
              ) else { return nil }
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = geometry.indices.count

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        guard let emptyTexture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        var clear: UInt32 = 0
        emptyTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clear, bytesPerRow: 4)
        self.emptyTexture = emptyTexture

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.sampler = sampler
    }

    func encode(encoder: MTLRenderCommandEncoder, uniforms: Uniforms, backdrop: MTLTexture?) {
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        // The mesh is closed and wound counter-clockwise from outside. The hollow shell draws its back wall first,
        // seen from inside, then its front wall over it; the depth test keeps the nearest of each.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(backdrop ?? emptyTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for cullMode in [MTLCullMode.front, .back] {
            encoder.setCullMode(cullMode)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }
    }

    /// The top turned by `yaw` about its own axis, the axis leaning by `lean` toward `leanDirection` and pivoting on the
    /// point at the origin, all seen from `pitch` above. Direction 0 leans to the right, as the mark does; it advances
    /// the way the top spins.
    nonisolated static func transform(yaw: Float, pitch: Float, lean: Float, leanDirection: Float) -> simd_float4x4 {
        let spin = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        // Leaning toward (cos ψ, 0, −sin ψ) turns the axis about up × that direction
        let leanAxis = SIMD3<Float>(-sin(leanDirection), 0, -cos(leanDirection))
        let tilt = simd_quatf(angle: lean, axis: leanAxis)
        let camera = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        return simd_float4x4(camera * tilt * spin)
    }
}
