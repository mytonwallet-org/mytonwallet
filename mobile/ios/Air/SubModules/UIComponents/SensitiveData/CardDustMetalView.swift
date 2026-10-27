import MetalKit
import UIKit

/// The same 64 opacity groups as the Core Graphics renderer, in one GPU draw.
/// Depth rejects overlaps within a group, preserving its union rather than
/// making dense patches brighter. Four samples keep the small dots antialiased.
@MainActor
final class CardDustMetalView: MTKView, MTKViewDelegate {
    private struct Uniforms {
        var size: SIMD2<Float>
        var padding = SIMD2<Float>.zero
        var gradient: SIMD4<Float>
    }
    @MainActor private final class Resources {
        static let shared = Resources()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        let depth: MTLDepthStencilState
        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), device.supportsTextureSampleCount(4),
                  let queue = device.makeCommandQueue() else { return nil }
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            guard let library = try? device.makeDefaultLibrary(bundle: bundle) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "cardDustVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "cardDustFragment")
            descriptor.rasterSampleCount = 4
            descriptor.depthAttachmentPixelFormat = .depth32Float
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .less
            depthDescriptor.isDepthWriteEnabled = true
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
                  let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
            self.device = device; self.queue = queue; self.pipeline = pipeline; self.depth = depth
        }
    }
    private let resources: Resources
    private let buffers: CardParticleBufferPool
    private var multisample: MTLTexture?
    private var depthTexture: MTLTexture?
    private var counts = Array(repeating: 0, count: 64)
    private var offsets = Array(repeating: 0, count: 64)
    private var colors = [SIMD4<Float>(1, 1, 1, 1)]
    private var geometry = SIMD4<Float>(0, 0, 1, 1)
    #if DEBUG
    private(set) var lastEncodeMilliseconds: Double = 0
    #endif
    private var revealed = false
    var samples: (() -> [CardSpoilerDustView.TransitionSample])?
    var onFirstFrame: (() -> Void)?

    init?(particleCapacity: Int) {
        guard particleCapacity == 6000, let resources = Resources.shared,
              let buffers = CardParticleBufferPool(device: resources.device, length: 6000 * MemoryLayout<SIMD4<Float>>.stride) else { return nil }
        self.resources = resources; self.buffers = buffers
        super.init(frame: .zero, device: resources.device)
        colorPixelFormat = .bgra8Unorm
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        isOpaque = false; backgroundColor = .clear
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isPaused = true; enableSetNeedsDisplay = true; framebufferOnly = true
        isUserInteractionEnabled = false; accessibilityElementsHidden = true
        alpha = 0; delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setPalette(color: UIColor, gradient: [UIColor]?, frame: CGRect, traits: UITraitCollection) {
        let palette = gradient != nil && frame.width > 0 ? gradient! : [color.withAlphaComponent(1)]
        colors = palette.map {
            let resolved = $0.resolvedColor(with: traits).cgColor
                .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
            let c = resolved?.components ?? [1, 1, 1, 1]
            return SIMD4(Float(c[0]), Float(c[1]), Float(c[2]), Float(c[3]))
        }
        if colors.isEmpty { colors = [.init(1, 1, 1, 1)] }
        let radial = MtwCardForegroundView.radialGeometry(in: frame, style: .balance)
        geometry = SIMD4(Float(radial.center.x), Float(radial.center.y), Float(max(1, radial.radius)), Float(colors.count))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard window != nil, !isHidden, UIApplication.shared.applicationState == .active,
              let samples else { return }
        guard let slot = buffers.acquire() else { setNeedsDisplay(); return }
        guard let drawable = currentDrawable, let command = resources.queue.makeCommandBuffer(),
              let pass = renderPass(texture: drawable.texture) else { buffers.release(slot.index); return }
        guard encode(samples(), size: bounds.size, pass: pass, command: command, reservedSlot: slot) else { return }
        if !revealed {
            command.addCompletedHandler { [weak self] command in
                guard command.status == .completed else { return }
                Task { @MainActor [weak self] in
                    guard let self, !revealed, window != nil else { return }
                    revealed = true
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    alpha = 1; onFirstFrame?()
                    CATransaction.commit()
                }
            }
        }
        command.present(drawable); command.commit()
    }

    private func renderPass(texture: MTLTexture) -> MTLRenderPassDescriptor? {
        if multisample?.width != texture.width || multisample?.height != texture.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat,
                width: texture.width, height: texture.height, mipmapped: false)
            descriptor.textureType = .type2DMultisample; descriptor.sampleCount = 4
            descriptor.storageMode = resources.device.supportsFamily(.apple1) ? .memoryless : .private
            descriptor.usage = .renderTarget
            multisample = resources.device.makeTexture(descriptor: descriptor)
            descriptor.pixelFormat = .depth32Float
            depthTexture = resources.device.makeTexture(descriptor: descriptor)
        }
        guard let multisample, let depthTexture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample
        pass.colorAttachments[0].resolveTexture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = clearColor
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        return pass
    }

    private func encode(_ samples: [CardSpoilerDustView.TransitionSample], size: CGSize,
                        pass: MTLRenderPassDescriptor, command: MTLCommandBuffer, reservedSlot: (index: Int, buffer: MTLBuffer)? = nil) -> Bool {
        #if DEBUG
        let started = CACurrentMediaTime()
        defer { lastEncodeMilliseconds = (CACurrentMediaTime() - started) * 1000 }
        #endif
        guard let slot = reservedSlot ?? buffers.acquire() else { setNeedsDisplay(); return false }
        guard size.width > 0, size.height > 0 else { buffers.release(slot.index); return false }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { buffers.release(slot.index); return false }
        for index in counts.indices { counts[index] = 0 }
        for sample in samples.prefix(6000) where sample.opacity > 0 {
            counts[min(63, max(0, Int((sample.opacity * 64).rounded()) - 1))] += 1
        }
        var total = 0
        for index in counts.indices { offsets[index] = total; total += counts[index] }
        let instances = slot.buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 6000)
        for sample in samples.prefix(6000) where sample.opacity > 0 {
            let bucket = min(63, max(0, Int((sample.opacity * 64).rounded()) - 1))
            instances[offsets[bucket]] = SIMD4(Float(sample.position.x), Float(sample.position.y),
                Float(sample.diameter / 2), Float(bucket + 1) / 64)
            offsets[bucket] += 1
        }
        var uniforms = Uniforms(size: SIMD2(Float(size.width), Float(size.height)), gradient: geometry)
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setDepthStencilState(resources.depth)
        encoder.setVertexBuffer(slot.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        colors.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: total)
        encoder.endEncoding()
        command.addCompletedHandler { [buffers, slotIndex = slot.index] _ in buffers.release(slotIndex) }
        return true
    }

    #if DEBUG
    func snapshotForValidation(samples: [CardSpoilerDustView.TransitionSample], size: CGSize, scale: CGFloat) -> UIImage? {
        let width = max(1, Int(size.width * scale)), height = max(1, Int(size.height * scale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
        guard let texture = resources.device.makeTexture(descriptor: descriptor), let command = resources.queue.makeCommandBuffer(),
              let pass = renderPass(texture: texture), encode(samples, size: size, pass: pass, command: command) else { return nil }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }
    #endif
}
