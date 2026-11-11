import Metal
import simd
import UIKit

/// Draws the spinning top: a hollow shell of frosted glass with a blue-to-purple coating, matte highlights, and the
/// captured content behind it seen through, blurred and tinted, clear toward the middle and denser toward the edge
@MainActor
final class SpinningTopRenderer {
    /// Matches `SpinningTopUniforms` in `AgentSpinningTop.metal`: one `float4x4` and five `float4`, 144 bytes
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
        /// `x`: iridescence 0…1; `y`: the motion blur's sweep, the angle the body turns in an exposure, in radians;
        /// `z`: speed streaks 0…1; `w`: reflection opacity, 0 for the top itself
        var effects: SIMD4<Float> = .zero
    }

    /// Matches `SpinningTopGroundUniforms` in `AgentSpinningTop.metal`: one `float4x4` and four `float4`, 128 bytes
    struct GroundUniforms {
        /// The camera alone, without the top's lean and spin
        var camera: simd_float4x4
        /// As the top's: the point in drawable pixels (y up), pixels per model unit, drawable height
        var placement: SIMD4<Float>
        /// `x`: drawable width; `yz`: the ground point under the rim's centre, model x and z
        var parameters: SIMD4<Float>
        /// `x`: the contact spot's strength; `y`: the body's; `z`: the body's radius in model units; `w`: a glow
        var shadow: SIMD4<Float>
        /// `rgb`: the shadow's or the glow's colour
        var color: SIMD4<Float>
    }

    /// The ground under a large top and its reflection in it
    struct Ground {
        var uniforms: GroundUniforms
        /// The top mirrored in the ground through its point, seen from the camera
        var reflection: simd_float4x4
        var reflectionOpacity: Float
    }

    let device: MTLDevice
    let sampleCount: Int
    private let pipeline: MTLRenderPipelineState
    private let groundPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let groundDepthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private let emptyTexture: MTLTexture
    private let sampler: MTLSamplerState

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.device = device
        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunction = library.makeFunction(name: "agentSpinningTopVertex"),
              let fragmentFunction = library.makeFunction(name: "agentSpinningTopFragment"),
              let groundVertexFunction = library.makeFunction(name: "agentSpinningTopGroundVertex"),
              let groundFragmentFunction = library.makeFunction(name: "agentSpinningTopGroundFragment") else { return nil }
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
        // The ground blends as the top does, premultiplied
        descriptor.vertexFunction = groundVertexFunction
        descriptor.fragmentFunction = groundFragmentFunction
        guard let groundPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.groundPipeline = groundPipeline

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.depthState = depthState
        let groundDepthDescriptor = MTLDepthStencilDescriptor()
        groundDepthDescriptor.depthCompareFunction = .always
        groundDepthDescriptor.isDepthWriteEnabled = false
        guard let groundDepthState = device.makeDepthStencilState(descriptor: groundDepthDescriptor) else { return nil }
        self.groundDepthState = groundDepthState

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

    /// Draws the top, and for a large top first the ground under it and its reflection in the ground
    func encode(encoder: MTLRenderCommandEncoder, uniforms: Uniforms, backdrop: MTLTexture?, ground: Ground? = nil) {
        if let ground {
            var groundUniforms = ground.uniforms
            encoder.setRenderPipelineState(groundPipeline)
            encoder.setDepthStencilState(groundDepthState)
            encoder.setCullMode(.none)
            encoder.setVertexBytes(&groundUniforms, length: MemoryLayout<GroundUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&groundUniforms, length: MemoryLayout<GroundUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            // The mirror flips the winding, so its outside faces clockwise; it takes the farther half of the depth range
            var reflection = uniforms
            reflection.rotation = ground.reflection
            reflection.effects.w = ground.reflectionOpacity
            encodeShell(encoder: encoder, uniforms: reflection, backdrop: backdrop, frontFacing: .clockwise)
        }
        var top = uniforms
        top.effects.w = 0
        encodeShell(encoder: encoder, uniforms: top, backdrop: backdrop, frontFacing: .counterClockwise)
    }

    private func encodeShell(
        encoder: MTLRenderCommandEncoder,
        uniforms: Uniforms,
        backdrop: MTLTexture?,
        frontFacing: MTLWinding
    ) {
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        // The mesh is closed and wound counter-clockwise from outside. The hollow shell draws its back wall first,
        // seen from inside, then its front wall over it; the depth test keeps the nearest of each.
        encoder.setFrontFacing(frontFacing)
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
    /// point at the origin, all seen from `pitch` above. Direction 0 leans to the right, as the mark does. A growing
    /// yaw and lean direction turn counter-clockwise as seen from above; the top, which spins clockwise, passes both
    /// negated.
    nonisolated static func transform(yaw: Float, pitch: Float, lean: Float, leanDirection: Float) -> simd_float4x4 {
        camera(pitch: pitch) * tiltAndSpin(yaw: yaw, lean: lean, leanDirection: leanDirection)
    }

    /// The top's lean and spin, without the camera
    nonisolated static func tiltAndSpin(yaw: Float, lean: Float, leanDirection: Float) -> simd_float4x4 {
        let spin = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        // Leaning toward (cos ψ, 0, −sin ψ) turns the axis about up × that direction
        let leanAxis = SIMD3<Float>(-sin(leanDirection), 0, -cos(leanDirection))
        let tilt = simd_quatf(angle: lean, axis: leanAxis)
        return simd_float4x4(tilt * spin)
    }

    /// The camera alone, `pitch` above the ground
    nonisolated static func camera(pitch: Float) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
    }

    /// The ground through the top's point under the top posed by `tiltAndSpin`, seen from `camera`, and its
    /// reflection: the look of the ground for the appearance, its reflection's matrix, and the ground point under the
    /// rim's centre
    nonisolated static func makeGround(
        tiltAndSpin: simd_float4x4,
        camera: simd_float4x4,
        placement: SIMD4<Float>,
        drawableWidth: Float,
        isDark: Bool
    ) -> Ground {
        let mirror = simd_float4x4(diagonal: SIMD4(1, -1, 1, 1))
        let axis = tiltAndSpin.columns.1
        let bodyCenter = SIMD2(axis.x, axis.z) * 0.53
        return Ground(
            uniforms: GroundUniforms(
                camera: camera,
                placement: placement,
                parameters: SIMD4(drawableWidth, bodyCenter.x, bodyCenter.y, 0),
                shadow: isDark ? SIMD4(0.35, 0.16, 0.32, 1) : SIMD4(0.5, 0.16, 0.3, 0),
                color: isDark ? SIMD4(0.2, 0.5, 1, 1) : SIMD4(0, 0, 0, 1)
            ),
            reflection: camera * mirror * tiltAndSpin,
            reflectionOpacity: isDark ? 0.6 : 0.45
        )
    }
}
