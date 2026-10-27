@preconcurrency import Metal
import MetalKit
import UIKit

/// One background triangle and optional star instances in one render pass.
/// The owner creates this only while motion is allowed;
/// static cards remain ordinary UIImageViews and retain no drawable or display link.
@MainActor
final class CardBackgroundMetalView: MTKView, MTKViewDelegate {
    private struct Uniforms: Equatable {
        var size: SIMD2<Float>
        var time: Float = 0
        var strength: Float = 0
        var seed: Float = 0
        var shine: Float = 0
        var tilt: SIMD2<Float> = .zero
        var shineStyle: UInt32 = 0
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
        var touchPosition: SIMD2<Float> = .zero
        var touchOpacity: Float = 0
        var touchExtent: Float = 0
        var linearBlur: Float = 0
        var experimentalShine: UInt32 = 0
        var surfaceTilt: SIMD2<Float> = .zero
        var customSurface: UInt32 = 0
        var starGrowth: UInt32 = 0
        var starBlend: UInt32 = 0
        var materialEnabled: UInt32 = 0
        var materialEnvironment: UInt32 = 0
        var materialPreset: UInt32 = 0
        var materialIntensity: Float = 0
        var materialBevel: Float = 0
        var materialEmboss: Float = 0
        var materialDepth: Float = 0
        var materialTilt: SIMD2<Float> = .zero
        var starAppearance = SIMD4<Float>(1.1, 0.65, 1, 1)
        var telegramShape = SIMD2<Float>(120, 18) // width in degrees, softness in points
        var gramControl = SIMD4<Float>(repeating: 0) // rotation, balance, behavior mode, v2 energy
        var gramLight = SIMD4<Float>(-0.35, 0.5, 1.4, 0)
        var gramView = SIMD4<Float>(0, 0, 1, 0)


        var backgroundCacheKey: Self {
            var key = self
            if strength == 0 { key.time = 0 }
            if blobCount == 0 { key.blobTime = 0 }
            key.activity = 0
            key.starGrowth = 0; key.starBlend = 0
            key.starAppearance = .zero
            return key
        }

        mutating func blendLight(from start: Self, progress p: Float) {
            shine = start.shine + (shine - start.shine) * p
            tilt = start.tilt + (tilt - start.tilt) * p
            activity = start.activity + (activity - start.activity) * p
            linearAngle = start.linearAngle + atan2(sin(linearAngle - start.linearAngle), cos(linearAngle - start.linearAngle)) * p
            touchPosition = start.touchPosition + (touchPosition - start.touchPosition) * p
            touchOpacity = start.touchOpacity + (touchOpacity - start.touchOpacity) * p
            touchExtent = start.touchExtent + (touchExtent - start.touchExtent) * p
            surfaceTilt = start.surfaceTilt + (surfaceTilt - start.surfaceTilt) * p
            materialTilt = start.materialTilt + (materialTilt - start.materialTilt) * p
            let angle = start.gramControl.x + atan2(sin(gramControl.x - start.gramControl.x), cos(gramControl.x - start.gramControl.x)) * p
            gramControl = start.gramControl + (gramControl - start.gramControl) * p
            gramControl.x = angle
            gramLight = start.gramLight + (gramLight - start.gramLight) * p
            gramView = start.gramView + (gramView - start.gramView) * p
        }
    }

    @MainActor private final class Resources {
        static let shared = Resources()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        let starPipeline: MTLRenderPipelineState
        let blendedStarsPipeline: MTLRenderPipelineState
        let plusStarsPipeline: MTLRenderPipelineState
        let copyPipeline: MTLRenderPipelineState
        let stars: MTLBuffer
        lazy var light: MTLTexture? = CardShineTexture.radial.flatMap {
            try? MTKTextureLoader(device: device).newTexture(cgImage: $0, options: [.SRGB: false])
        }
        lazy var brush: MTLTexture? = CardBrushTexture.radial.cgImage.flatMap {
            try? MTKTextureLoader(device: device).newTexture(cgImage: $0, options: [.SRGB: false])
        }
        private let textures = NSCache<NSString, Texture>()

        private final class Texture {
            let value: MTLTexture
            init(_ value: MTLTexture) { self.value = value }
        }

        private init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                  let library = try? device.makeDefaultLibrary(bundle: .module) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "cardBackgroundVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "cardBackgroundFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            descriptor.vertexFunction = library.makeFunction(name: "cardStarVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "cardStarFragment")
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let starPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
                  let stars = device.makeBuffer(bytes: CardStarField.stars,
                    length: MemoryLayout<CardStarField.Star>.stride * CardStarField.stars.count) else { return nil }
            descriptor.fragmentFunction = library.makeFunction(name: "cardStarBlendFragment")
            guard let blendedStarsPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            descriptor.fragmentFunction = library.makeFunction(name: "cardStarFragment")
            attachment.destinationRGBBlendFactor = .one
            guard let plusStarsPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            attachment.isBlendingEnabled = false
            descriptor.vertexFunction = library.makeFunction(name: "cardBackgroundVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "cardCopyFragment")
            guard let copyPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            self.blendedStarsPipeline = blendedStarsPipeline
            self.plusStarsPipeline = plusStarsPipeline
            self.copyPipeline = copyPipeline
            self.device = device
            self.queue = queue
            self.pipeline = pipeline
            self.starPipeline = starPipeline
            self.stars = stars
            textures.totalCostLimit = 16 * 1_024 * 1_024
            textures.countLimit = 16
        }

        func touchSpot(cardWidth: CGFloat, blur: CGFloat, area: CGFloat) -> MTLTexture? {
            let key = "touch-spot:\(Int(cardWidth.rounded())):\(blur):\(area)" as NSString
            if let cached = textures.object(forKey: key) { return cached.value }
            guard let image = CardShineTexture.touchSpot(cardWidth: cardWidth, blur: blur, area: area),
                  let value = try? MTKTextureLoader(device: device).newTexture(cgImage: image, options: [.SRGB: false]) else { return nil }
            textures.setObject(Texture(value), forKey: key, cost: image.width * image.height * 4)
            return value
        }

        func texture(image: CGImage, cardId: String, srgb: Bool = true) -> MTLTexture? {
            let key = "\(cardId):\(image.width):\(image.height):\(srgb)" as NSString
            if let cached = textures.object(forKey: key) { return cached.value }
            // ImageRenderer's opaque RGBX image is not accepted by MTKTextureLoader.
            // Normalize once to sRGB RGBA8 and upload bytes directly, without a decoder.
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                  let bytes = context.data else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: srgb ? .rgba8Unorm_srgb : .rgba8Unorm,
                width: image.width, height: image.height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                            withBytes: bytes, bytesPerRow: context.bytesPerRow)
            textures.setObject(Texture(texture), forKey: key, cost: context.bytesPerRow * image.height)
            return texture
        }
    }

    private let resources: Resources
    private let texture: MTLTexture
    private let motionSeed: UInt32?
    private let hasStars: Bool
    private let spots: [MTLTexture]
    private let contrastOpacity: Float
    private let contrastColor: Float
    private var light = CardSurfaceLight()
    private var shineEnabled = false
    private var surface = CardSurfaceConfiguration.myWallet
    private var lightTexture: MTLTexture?
    private var brushTexture: MTLTexture?
    private var touchSpotTexture: MTLTexture?
    private var touchSpotWidth: CGFloat = 0
    private var touchSpotKey = ""
    private var blendBackdrop: MTLTexture?
    private var blendBackdropKey: Uniforms?
    private(set) var backgroundPassCount = 0
    private var animatesBackground = false
    private var needsBackgroundFrames: Bool { animatesBackground && (motionSeed != nil || hasStars) }
    private(set) var submittedFrameCount = 0
    private var hasRenderedFrame = false
    private var redrawPending = false
    private(set) var isSuspended = false
    private(set) var clock = CardBackgroundAnimationClock()
    private var lastUniforms: Uniforms?
    private var resumeUniforms: Uniforms?
    private var resumeStartedAt: CFTimeInterval?
    private var interactiveUntil: CFTimeInterval = 0
    private var previousTime: CFTimeInterval?
    private var previewFrame: (time: Double, strength: Double)?
    private let inFlight = DispatchSemaphore(value: 2)

    init?(image: UIImage, seed: CardBackgroundSeed?, showContrast: Bool = true,
          defaultArtwork: CardSurfaceConfiguration.DefaultArtwork = .myWallet,
          clock: CardBackgroundAnimationClock = CardBackgroundAnimationClock()) {
        guard let resources = Resources.shared else { return nil }
        let layers: CardBackgroundLayers?
        if let seed {
            layers = try? CardBackgroundRenderer.shared.layers(seed: seed, showContrast: showContrast)
        } else {
            layers = CardDefaultBackground.artwork(defaultArtwork).layers
        }
        let cardId = seed?.cardId ?? "home-default-\(defaultArtwork.rawValue)"
        guard let cgImage = (layers?.base ?? image).cgImage,
              let texture = resources.texture(image: cgImage, cardId: "\(cardId):\(layers == nil ? "flat" : "base")") else { return nil }
        self.resources = resources
        self.clock = clock
        self.texture = texture
        self.motionSeed = seed?.motionSeed
        self.hasStars = seed == nil && defaultArtwork == .gramWallet
        var spots: [MTLTexture] = []
        for (index, image) in (layers?.spots ?? []).enumerated() {
            guard let cgImage = image.cgImage,
                  let spot = resources.texture(image: cgImage, cardId: "\(cardId):spot\(index)", srgb: false) else { return nil }
            spots.append(spot)
        }
        self.spots = spots
        self.contrastOpacity = layers?.contrastOpacity ?? 0
        self.contrastColor = layers?.contrastColor ?? -1
        super.init(frame: .zero, device: resources.device)
        colorPixelFormat = .bgra8Unorm_srgb
        framebufferOnly = true
        autoResizeDrawable = false
        let scale = min(1, 800 / Double(texture.width))
        drawableSize = CGSize(width: Double(texture.width) * scale, height: Double(texture.height) * scale)
        preferredFramesPerSecond = 30
        isPaused = true
        alpha = 0
        isOpaque = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(animateBackground: Bool, shine: Bool, light: CardSurfaceLight, surface: CardSurfaceConfiguration, animateResume: Bool = false) {
        if isSuspended {
            resumeUniforms = animateResume ? lastUniforms : nil
            resumeStartedAt = nil
        }
        if isSuspended || animatesBackground != animateBackground { previousTime = nil }
        previewFrame = nil
        isSuspended = false
        animatesBackground = animateBackground
        shineEnabled = shine
        self.light = light
        self.surface = surface
        updateDrawableSize()
        lightTexture = surface.shine == .radial && surface.motion?.gramTelegramShine != true ? resources.light : nil
        prepareTouchSpot()
        brushTexture = surface.radialBrush ? resources.brush : nil
        isPaused = !needsBackgroundFrames && resumeUniforms == nil
        enableSetNeedsDisplay = isPaused
        if isPaused {
            // A transparent MTKView may not receive setNeedsDisplay until visible.
            // Bootstrap its first frame synchronously; coalesce subsequent inputs.
            if lastUniforms == nil || alpha == 0 { draw() }
            else { requestFrame() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
        prepareTouchSpot()
    }

    private func updateDrawableSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        let next = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        if drawableSize != next { drawableSize = next }
    }

    private func prepareTouchSpot() {
        guard surface.touchSpotEnabled else {
            touchSpotTexture = nil
            touchSpotWidth = 0
            touchSpotKey = ""
            return
        }
        let width = bounds.width.rounded()
        let blur = CGFloat(surface.motion?.touchGlowBlur ?? 28), area = CGFloat(surface.motion?.touchGlowArea ?? 1)
        let key = "\(width):\(blur):\(area)"
        guard width > 0, key != touchSpotKey else { return }
        touchSpotTexture = resources.touchSpot(cardWidth: width, blur: blur, area: area)
        touchSpotWidth = width
        touchSpotKey = key
    }

    func showFrame(time: Double, strength: Double, blobMotion: CardBlobMotion = .cardCenter) {
        isSuspended = false
        resumeUniforms = nil
        surface.blobMotion = blobMotion
        previewFrame = (max(0, time), max(0, strength))
        isPaused = true
        enableSetNeedsDisplay = true
        draw()
    }

    func setLight(_ light: CardSurfaceLight) {
        let visible = surface.motion?.materialEnabled == true || surface.shine == .radial || self.light.activity > 0 || light.activity > 0
            || self.light.touchSpot != nil || light.touchSpot != nil
        let changed = visible && !self.light.visuallyMatches(light)
        self.light = light
        if changed || light.press > 0 {
            interactiveUntil = CACurrentMediaTime() + 0.4
            if preferredFramesPerSecond != 60 { preferredFramesPerSecond = 60 }
        }
        // Idle backgrounds stay at 30 Hz; input and its settling tail render at 60 Hz.
        if !isSuspended, isPaused, changed, (shineEnabled || surface.motion?.materialEnabled == true || surface.touchSpotEnabled) { requestFrame() }
    }

    private func requestFrame(retry: Bool = false) {
        guard !redrawPending, isPaused, !isSuspended else { return }
        redrawPending = true
        // Coalesce light changes without relying on UIKit invalidating a paused MTKView.
        let delay = retry ? 1 / Double(max(1, preferredFramesPerSecond)) : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.redrawPending = false
            guard self.isPaused, !self.isSuspended else { return }
            self.draw()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func pause() {
        isSuspended = true
        isPaused = true
        enableSetNeedsDisplay = false
        previousTime = nil
    }

    func draw(in view: MTKView) {
        guard !isSuspended, UIApplication.shared.applicationState != .background,
              window != nil, bounds.width > 0, bounds.height > 0 else { return }
        let now = CACurrentMediaTime()
        let rate = resumeUniforms != nil || now < interactiveUntil ? 60 : 30
        if preferredFramesPerSecond != rate { preferredFramesPerSecond = rate }
        if needsBackgroundFrames, previewFrame == nil, let previousTime {
            clock.advance(by: min(0.1, max(0, now - previousTime)), press: light.press, activity: light.activity)
        }
        previousTime = now
        guard inFlight.wait(timeout: .now()) == .success else {
            // Keep the final touch/light pose even when an on-demand frame was skipped.
            if isPaused { requestFrame(retry: true) }
            return
        }
        guard let descriptor = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = resources.queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let preset = surface.motion
        let spot = preset == nil && surface.touchSpotEnabled ? light.touchSpot : nil
        let opacity = (surface.shine == .radial ? preset?.gramOpacity : preset?.shineOpacity) ?? surface.shineOpacity
        let lightActivity = surface.shine == .linear ? Float(light.activity)
            : (lightTexture == nil && preset?.gramTelegramShine != true ? 0 : 1)
        let intensity: Float = (!shineEnabled || preset?.shineEnabled == false) ? 0
            : (spot.map { touchSpotTexture == nil ? 0 : Float($0.opacity) } ?? opacity * lightActivity)
        let tilt = spot.map { SIMD2(Float($0.position.x), Float($0.position.y)) }
            ?? (surface.shine == .linear ? SIMD2<Float>(0, Float(light.linearPosition ?? -light.tilt.y))
                : SIMD2(Float(light.tilt.x), Float(light.tilt.y)))
        var uniforms = Uniforms(size: SIMD2(Float(bounds.width), Float(bounds.height)),
                                time: Float(previewFrame?.time ?? clock.lineTime),
                                strength: Float(previewFrame?.strength ?? (animatesBackground && motionSeed != nil ? CardBackgroundMotion.defaultStrength : 0)),
                                seed: Float((motionSeed ?? 0) % 65_536) / 65_536,
                                shine: intensity, tilt: tilt,
                                shineStyle: spot == nil ? (preset?.gramTelegramShine == true ? 3 : surface.shine.rawValue) : 2,
                                linearWidth: spot == nil ? max(0.02, surface.linearWidth)
                                    : Float(CardShineTexture.touchSpotExtent(cardWidth: touchSpotWidth) / bounds.width),
                                brush: brushTexture == nil ? 0 : 0.15,
                                blobTime: Float(previewFrame.map { $0.strength > 0 ? $0.time / CardBackgroundMotion.defaultSpeed : 0 }
                                    ?? (animatesBackground ? clock.blobTime : 0)),
                                blobCount: UInt32(spots.count), contrastOpacity: contrastOpacity, contrastColor: contrastColor,
                                blobMotion: surface.blobMotion.rawValue, activity: Float(light.activity),
                                linearAngle: Float(light.linearAngle ?? CGFloat(surface.linearAngle)) * .pi / 180)
        if let preset {
            uniforms.linearBlur = preset.linearBlur
            uniforms.experimentalShine = preset.experimentalShine ? 1 : 0
            uniforms.surfaceTilt = SIMD2(Float(light.tilt.x), Float(light.tilt.y))
            uniforms.customSurface = motionSeed == nil ? 0 : 1
            uniforms.starGrowth = preset.gramStarGrowth ? 1 : 0
            uniforms.starBlend = UInt32(preset.gramStarBlend)
            uniforms.starAppearance = SIMD4(preset.gramStarSizeIn, preset.gramStarSizeOut, preset.gramStarOpacityIn, preset.gramStarOpacityOut)
            uniforms.telegramShape = SIMD2(preset.gramWidth, preset.gramBlur)
            if preset.gramReflectionMode != .current {
                let reflection = light.gramReflection ?? CardGramReflectionPose()
                uniforms.gramControl = SIMD4(Float(reflection.rotation), Float(reflection.balance), Float(preset.gramReflectionMode.rawValue), Float(reflection.energy))
                uniforms.gramLight = SIMD4(reflection.light, 0); uniforms.gramView = SIMD4(reflection.view, 0)
            }
            uniforms.materialEnabled = preset.materialEnabled ? 1 : 0
            uniforms.materialEnvironment = UInt32(preset.materialEnvironment)
            uniforms.materialPreset = UInt32(preset.materialPreset)
            uniforms.materialIntensity = preset.materialIntensity
            uniforms.materialBevel = preset.materialBevel; uniforms.materialEmboss = preset.materialEmboss
            uniforms.materialDepth = preset.materialDepth
            let materialTilt = light.borderTilt ?? light.tilt
            uniforms.materialTilt = SIMD2(Float(materialTilt.x), Float(materialTilt.y))
            if preset.touchGlow, let touch = light.touchSpot, touchSpotTexture != nil {
                uniforms.touchPosition = SIMD2(Float(touch.position.x), Float(touch.position.y))
                uniforms.touchOpacity = Float(touch.opacity) * preset.touchGlowIntensity
                uniforms.touchExtent = Float(CardShineTexture.touchSpotExtent(cardWidth: touchSpotWidth, blur: CGFloat(preset.touchGlowBlur), area: CGFloat(preset.touchGlowArea)))
            }
        }
        if let start = resumeUniforms {
            if resumeStartedAt == nil { resumeStartedAt = now }
            let elapsed = now - (resumeStartedAt ?? now)
            uniforms.blendLight(from: start, progress: Float(CardSurfaceLight.resumeProgress(elapsed: elapsed)))
            if elapsed >= CardSurfaceLight.resumeDuration {
                resumeUniforms = nil
                resumeStartedAt = nil
                if !needsBackgroundFrames { isPaused = true; enableSetNeedsDisplay = true }
            }
        }
        lastUniforms = uniforms
        guard encode(uniforms, descriptor: descriptor, command: command, width: drawable.texture.width, height: drawable.texture.height) else { inFlight.signal(); return }
        submittedFrameCount += 1
        command.present(drawable)
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        if !hasRenderedFrame {
            command.addCompletedHandler { [weak self] command in
                guard command.status == .completed else { return }
                Task { @MainActor [weak self] in self?.revealFirstFrame() }
            }
        }
        command.commit()
    }

    /// Render once into readable storage when pausing. No drawable readback, per-frame
    /// copies, or main-thread GPU waits; the existing artwork remains visible meanwhile.
    func snapshot(completion: @escaping @MainActor (UIImage?) -> Void) {
        pause()
        guard UIApplication.shared.applicationState != .background,
              let uniforms = lastUniforms else { completion(nil); return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat,
            width: Int(drawableSize.width), height: Int(drawableSize.height), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let texture = resources.device.makeTexture(descriptor: descriptor),
              let command = resources.queue.makeCommandBuffer() else { completion(nil); return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard encode(uniforms, descriptor: pass, command: command, width: texture.width, height: texture.height) else { completion(nil); return }
        command.addCompletedHandler { command in
            let image = command.status == .completed ? Self.image(from: texture) : nil
            Task { @MainActor in completion(image.map { UIImage(cgImage: $0, scale: 2, orientation: .up) }) }
        }
        command.commit()
    }

    nonisolated private static func image(from texture: MTLTexture) -> CGImage? {
        let rowBytes = texture.width * 4
        var data = Data(count: rowBytes * texture.height)
        data.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: rowBytes, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func encode(_ frame: Uniforms, descriptor: MTLRenderPassDescriptor, command: MTLCommandBuffer, width: Int, height: Int) -> Bool {
        var backdrop: MTLTexture?
        if hasStars, frame.starBlend == 1 {
            if blendBackdrop?.width != width || blendBackdrop?.height != height {
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat, width: width, height: height, mipmapped: false)
                textureDescriptor.usage = [.renderTarget, .shaderRead]; textureDescriptor.storageMode = .private
                blendBackdrop = resources.device.makeTexture(descriptor: textureDescriptor)
                blendBackdropKey = nil
            }
            guard let texture = blendBackdrop else { return false }
            if blendBackdropKey != frame.backgroundCacheKey {
                let backgroundPass = MTLRenderPassDescriptor()
                backgroundPass.colorAttachments[0].texture = texture
                backgroundPass.colorAttachments[0].loadAction = .dontCare
                backgroundPass.colorAttachments[0].storeAction = .store
                guard let encoder = command.makeRenderCommandEncoder(descriptor: backgroundPass) else { return false }
                encode(frame, using: encoder, drawStars: false)
                backgroundPassCount += 1
            }
            backdrop = texture
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encode(frame, using: encoder, drawStars: true, backdrop: backdrop)
        if backdrop != nil { blendBackdropKey = frame.backgroundCacheKey }
        return true
    }

    private func encode(_ frame: Uniforms, using encoder: MTLRenderCommandEncoder, drawStars: Bool, backdrop: MTLTexture? = nil) {
        var uniforms = frame
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if let backdrop {
            encoder.setRenderPipelineState(resources.copyPipeline)
            encoder.setFragmentTexture(backdrop, index: 7)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        } else {
            encoder.setRenderPipelineState(resources.pipeline)
            for index in 0...6 { encoder.setFragmentTexture(texture, index: index) }
            encoder.setFragmentTexture((frame.shineStyle == 2 ? touchSpotTexture : lightTexture) ?? texture, index: 1)
            encoder.setFragmentTexture(brushTexture ?? texture, index: 2)
            encoder.setFragmentTexture(touchSpotTexture ?? texture, index: 6)
            for (index, spot) in spots.enumerated() { encoder.setFragmentTexture(spot, index: index + 3) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if drawStars && hasStars {
            encoder.setRenderPipelineState(frame.starBlend == 2 ? resources.plusStarsPipeline : (backdrop == nil ? resources.starPipeline : resources.blendedStarsPipeline))
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setVertexBuffer(resources.stars, offset: 0, index: 1)
            encoder.setVertexTexture(lightTexture ?? texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: CardStarField.stars.count)
        }
        encoder.endEncoding()
    }

    private func revealFirstFrame() {
        guard !hasRenderedFrame, window != nil else { return }
        hasRenderedFrame = true
        alpha = 1
        // Keep the cached artwork visible until Metal is ready. Core Animation fades
        // in the rendered frame without waking the on-demand renderer every frame.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.3
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "cardAppearance")
    }
}
