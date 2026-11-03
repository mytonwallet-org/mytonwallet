import Metal
import MetalKit
import QuartzCore
import UIKit

/// Telegram's dust, which a deleted message turns into: each item handed over comes apart from left to right into
/// grains that tremble loose, drift up on soft currents of air, dwindle to glittering pixels and go out.
///
/// The view covers the container its items are in and draws them in its own coordinates. It runs frames only while it
/// has items and is in a window, frees each item's buffers once its grains are gone, and calls `becameEmpty` when the
/// last one goes, so the owner can remove it. Where Metal or the effect's pipelines are unavailable, `isAvailable` is
/// `false` and `addItem(frame:image:)` takes nothing.
public final class DustEffectView: UIView {
    /// Matches `ParticleFluidParams` in `DustEffectShaders.metal`
    private struct ParticleFluidParams {
        var itemOrigin: SIMD2<Float>
        var itemSize: SIMD2<Float>
        var cellSize: Float
        var isEnabled: Float
    }

    private final class Item {
        let frame: CGRect
        let texture: MTLTexture

        var phase: Float = 0
        var duration: Double = 0
        var isParticleBufferInitialized: Bool = false
        var particleBuffer: MTLBuffer?

        init?(frame: CGRect, image: UIImage, textureLoader: MTKTextureLoader) {
            guard let cgImage = image.cgImage,
                  let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [.SRGB: false as NSNumber]) else {
                return nil
            }
            self.frame = frame
            self.texture = texture
        }
    }

    /// The shaders draw a fully dwindled grain as one pixel at 3x, a third of a point
    private static let maximumRenderScale: CGFloat = 3
    /// The frame that shows new items, presented with the transaction that hides their sources, waits this long for
    /// the GPU rather than skip
    private static let transactionFrameWait: TimeInterval = 0.05
    private static let animationSpeed: Float = 1.0
    /// The grains rise
    private static let verticalDirection: Float = 1.0
    /// The drawable covers the whole layer
    private static let placement = CGRect(x: 0, y: 0, width: 1, height: 1)

    public static var isAvailable: Bool {
        DustEffectRenderer.shared != nil
    }

    public var becameEmpty: (() -> Void)?

    private let renderer = DustEffectRenderer.shared
    private var items: [Item] = []
    private lazy var clock = GlassMotionClock { [weak self] _ in self?.tick() }
    private var lastTimeStep: Double = 0.0
    private var lastUpdateTimestamp: Double?
    private var fluid: DustFluidSimulation?
    private var pendingFluidSplats: [DustFluidSimulation.Splat] = []
    private var randomGenerator = SystemRandomNumberGenerator()
    private var isTransactionFrameNeeded = false
    private let inFlight = DispatchSemaphore(value: 2)

    override public class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    private var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        if let metalLayer {
            metalLayer.device = renderer?.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = false
            // The snapshots handed over are sRGB
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Dissolves `image`, a snapshot of what stood at `frame` in this view's coordinates. Its first frame shows with
    /// the current Core Animation transaction, so the caller hides the source in the same one. Returns `false` when
    /// the effect is unavailable or cannot take the image, and the source should go another way.
    @discardableResult
    public func addItem(frame: CGRect, image: UIImage) -> Bool {
        guard let renderer, Int(frame.width) > 0, Int(frame.height) > 0,
              let item = Item(frame: frame, image: image, textureLoader: renderer.textureLoader) else {
            return false
        }
        items.append(item)
        updateNeedsAnimation()
        isTransactionFrameNeeded = true
        setNeedsLayout()
        return true
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        updateNeedsAnimation()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
        if isTransactionFrameNeeded {
            isTransactionFrameNeeded = false
            render(shouldPresentWithTransaction: true)
        }
    }

    private func tick() {
        updateItems(deltaTime: clock.frameDuration)
        render(shouldPresentWithTransaction: false)
    }

    private func updateDrawableSize() {
        guard let metalLayer else { return }
        let scale = min(Self.maximumRenderScale, max(1, traitCollection.displayScale))
        let size = CGSize(width: max(1, ceil(bounds.width * scale)), height: max(1, ceil(bounds.height * scale)))
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }

    private func updateItems(deltaTime: Double) {
        let timestamp = CACurrentMediaTime()
        let localDeltaTime: Double
        if let lastUpdateTimestamp {
            localDeltaTime = timestamp - lastUpdateTimestamp
        } else {
            localDeltaTime = 0.0
        }
        lastUpdateTimestamp = timestamp

        let deltaTimeValue: Double
        if localDeltaTime <= 0.001 || localDeltaTime >= 0.2 {
            deltaTimeValue = deltaTime
        } else {
            deltaTimeValue = localDeltaTime
        }

        // Adds up until a frame is rendered, so a frame the GPU was too busy to take loses no time
        lastTimeStep += deltaTimeValue

        let containerHeight = Float(bounds.height)

        var hasRemovedItems = false
        for index in (0 ..< items.count).reversed() {
            let item = items[index]
            let previousPhase = item.phase
            item.phase += Float(deltaTimeValue) * Self.animationSpeed
            item.duration += deltaTimeValue

            // The last grains come loose when the sweep ends, at phase 0.8, and then live for up to 2.1 seconds (4.1
            // in their simulation time, which runs twice as fast; see `dustEffectInitializeParticle`) whatever the speed
            if item.phase >= 4.0 && item.duration >= 0.8 / Double(Self.animationSpeed) + 2.1 {
                items.remove(at: index)
                hasRemovedItems = true
            } else {
                let itemOrigin = SIMD2<Float>(Float(item.frame.minX), containerHeight - Float(item.frame.maxY))
                let itemSize = SIMD2<Float>(Float(item.frame.width), Float(item.frame.height))
                let splats = DustFluidSimulation.dissolveSplats(itemOrigin: itemOrigin, itemSize: itemSize, previousPhase: previousPhase, phase: item.phase, verticalDirection: Self.verticalDirection, generator: &randomGenerator)
                pendingFluidSplats.append(contentsOf: splats)
            }
        }
        updateNeedsAnimation()

        if hasRemovedItems && items.isEmpty {
            fluid = nil
            pendingFluidSplats.removeAll()
            becameEmpty?()
        }
    }

    private func updateNeedsAnimation() {
        if !items.isEmpty && window != nil {
            clock.start()
        } else {
            clock.stop()
        }
    }

    private func render(shouldPresentWithTransaction: Bool) {
        // Work submitted to the GPU from the background is rejected
        guard let renderer, let metalLayer, window != nil, UIApplication.shared.applicationState != .background,
              bounds.width > 0, bounds.height > 0 else { return }
        let deadline: DispatchTime = shouldPresentWithTransaction ? .now() + Self.transactionFrameWait : .now()
        guard inFlight.wait(timeout: deadline) == .success else { return }
        guard let commandBuffer = renderer.queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        commandBuffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }

        let containerSize = bounds.size

        for item in items where item.particleBuffer == nil {
            let particleCount = Int(item.frame.width) * Int(item.frame.height)
            // `Particle` in `DustEffectShaders.metal`: offset, velocity, lifetime, age, displacement
            item.particleBuffer = renderer.device.makeBuffer(length: particleCount * 4 * (2 + 2 + 1 + 1 + 2), options: .storageModeShared)
        }

        let fluidSize = SIMD2<Float>(Float(containerSize.width), Float(containerSize.height))
        if !items.isEmpty && fluid?.size != fluidSize {
            fluid = DustFluidSimulation(device: renderer.device, size: fluidSize)
        }

        let lastTimeStep = self.lastTimeStep
        self.lastTimeStep = 0.0

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            encodeSimulation(computeEncoder, renderer: renderer, lastTimeStep: lastTimeStep, containerSize: containerSize)
            computeEncoder.endEncoding()
        }

        metalLayer.presentsWithTransaction = shouldPresentWithTransaction
        guard let drawable = metalLayer.nextDrawable() else {
            metalLayer.presentsWithTransaction = false
            commandBuffer.commit()
            return
        }
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
            renderEncoder.setRenderPipelineState(renderer.renderPipeline)
            encodeParticles(renderEncoder, containerSize: containerSize)
            renderEncoder.endEncoding()
        }

        if shouldPresentWithTransaction {
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable.present()
            metalLayer.presentsWithTransaction = false
        } else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func encodeSimulation(_ computeEncoder: MTLComputeCommandEncoder, renderer: DustEffectRenderer, lastTimeStep: Double, containerSize: CGSize) {
        var verticalDirection = Self.verticalDirection

        let fluid = self.fluid
        if let fluid, lastTimeStep != 0.0 {
            var timeStep = Float(lastTimeStep)
            timeStep *= 2.0
            fluid.encode(encoder: computeEncoder, pipelines: renderer.fluidPipelines, timeStep: timeStep, splats: pendingFluidSplats)
            pendingFluidSplats.removeAll()
        }

        for item in items {
            guard let particleBuffer = item.particleBuffer else {
                continue
            }

            let itemFrame = item.frame
            let particleColumnCount = Int(itemFrame.width)
            let particleRowCount = Int(itemFrame.height)
            var particleCount = SIMD2<UInt32>(UInt32(particleColumnCount), UInt32(particleRowCount))

            let threadgroupSize = MTLSize(width: 32, height: 1, depth: 1)
            let threadgroupCount = MTLSize(width: (particleRowCount * particleColumnCount + threadgroupSize.width - 1) / threadgroupSize.width, height: 1, depth: 1)

            computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)

            if !item.isParticleBufferInitialized {
                item.isParticleBufferInitialized = true
                computeEncoder.setComputePipelineState(renderer.initializeParticlePipeline)
                computeEncoder.setBytes(&verticalDirection, length: 4, index: 1)
                computeEncoder.setBytes(&particleCount, length: 4 * 2, index: 2)
                computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            }

            if lastTimeStep != 0.0 {
                computeEncoder.setComputePipelineState(renderer.updateParticlePipeline)
                computeEncoder.setBytes(&particleCount, length: 4 * 2, index: 1)
                var phase = item.phase
                computeEncoder.setBytes(&phase, length: 4, index: 2)
                var timeStep = Float(lastTimeStep)
                timeStep *= 2.0
                computeEncoder.setBytes(&timeStep, length: 4, index: 3)
                computeEncoder.setBytes(&verticalDirection, length: 4, index: 4)

                var fluidParameters = ParticleFluidParams(
                    itemOrigin: SIMD2<Float>(Float(itemFrame.minX), Float(containerSize.height - itemFrame.maxY)),
                    itemSize: SIMD2<Float>(Float(itemFrame.width), Float(itemFrame.height)),
                    cellSize: fluid?.cellSize ?? 1.0,
                    isEnabled: fluid != nil ? 1.0 : 0.0
                )
                computeEncoder.setBytes(&fluidParameters, length: MemoryLayout<ParticleFluidParams>.stride, index: 5)
                // Without a fluid the kernel does not read the texture, but one must still be bound
                computeEncoder.setTexture(fluid?.streamFunctionTexture ?? item.texture, index: 0)
                computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            }
        }
    }

    private func encodeParticles(_ encoder: MTLRenderCommandEncoder, containerSize: CGSize) {
        for item in items {
            guard let particleBuffer = item.particleBuffer else {
                continue
            }

            var itemFrame = item.frame
            itemFrame.origin.y = containerSize.height - itemFrame.maxY

            let particleColumnCount = Int(itemFrame.width)
            let particleRowCount = Int(itemFrame.height)
            let particleCount = particleColumnCount * particleRowCount

            var effectiveRect = Self.placement
            effectiveRect.origin.x += itemFrame.minX / containerSize.width * effectiveRect.width
            effectiveRect.origin.y += itemFrame.minY / containerSize.height * effectiveRect.height
            effectiveRect.size.width = itemFrame.width / containerSize.width * effectiveRect.width
            effectiveRect.size.height = itemFrame.height / containerSize.height * effectiveRect.height

            var rect = SIMD4<Float>(Float(effectiveRect.minX), Float(effectiveRect.minY), Float(effectiveRect.width), Float(effectiveRect.height))
            encoder.setVertexBytes(&rect, length: 4 * 4, index: 0)

            var size = SIMD2<Float>(Float(itemFrame.width), Float(itemFrame.height))
            encoder.setVertexBytes(&size, length: 4 * 2, index: 1)

            var particleResolution = SIMD2<UInt32>(UInt32(particleColumnCount), UInt32(particleRowCount))
            encoder.setVertexBytes(&particleResolution, length: 4 * 2, index: 2)

            encoder.setVertexBuffer(particleBuffer, offset: 0, index: 3)

            encoder.setFragmentTexture(item.texture, index: 0)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: particleCount)
        }
    }
}

/// The Metal objects all dust effects share: the device, its queue and the effect's pipelines
@MainActor
private final class DustEffectRenderer {
    static let shared = DustEffectRenderer()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let textureLoader: MTKTextureLoader
    let renderPipeline: MTLRenderPipelineState
    let initializeParticlePipeline: MTLComputePipelineState
    let updateParticlePipeline: MTLComputePipelineState
    let fluidPipelines: DustFluidSimulation.Pipelines

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFunction = library.makeFunction(name: "dustEffectVertex"),
              let fragmentFunction = library.makeFunction(name: "dustEffectFragment"),
              let initializeParticleFunction = library.makeFunction(name: "dustEffectInitializeParticle"),
              let updateParticleFunction = library.makeFunction(name: "dustEffectUpdateParticle") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        guard let renderPipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor),
              let initializeParticlePipeline = try? device.makeComputePipelineState(function: initializeParticleFunction),
              let updateParticlePipeline = try? device.makeComputePipelineState(function: updateParticleFunction),
              let fluidPipelines = DustFluidSimulation.Pipelines(library: library, makePipelineState: { function in
                  try? device.makeComputePipelineState(function: function)
              }) else {
            return nil
        }

        self.device = device
        self.queue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        self.renderPipeline = renderPipeline
        self.initializeParticlePipeline = initializeParticlePipeline
        self.updateParticlePipeline = updateParticlePipeline
        self.fluidPipelines = fluidPipelines
    }
}
