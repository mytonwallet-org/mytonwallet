import MetalKit
import WalletContext

extension CardBackgroundAnimationEnvironment {
    var diamondAnimationsEnabled: Bool {
        CardBackgroundMotionPolicy(requested: true, animationsEnabled: animationsEnabled,
            lowPowerMode: lowPowerMode, reduceMotion: reduceMotion,
            applicationActive: applicationActive, visible: true).canAnimate
    }
}

@MainActor private enum TelegramDiamondResources {
    static let renderer = MTLCreateSystemDefaultDevice().flatMap { DiamondRenderer(device: $0) }
    static let queue = renderer?.device.makeCommandQueue()
    static let haptic = UIImpactFeedbackGenerator(style: .light)
}

/// UIKit/MetalKit host for Telegram's unmodified geometry, animation and shader code.
final class TelegramDiamondMetalView: MTKView, MTKViewDelegate {
    static var isAvailable: Bool {
        TelegramDiamondResources.renderer != nil && TelegramDiamondResources.queue != nil
    }

    private let renderer: DiamondRenderer
    private let queue: MTLCommandQueue
    private let renderTargets = DiamondRenderTargetCache()
    private var style = DiamondStyle()
    private var motion = DiamondMotion()
    private var lastTime: CFTimeInterval?
    private var elapsed: Float = 0
    private var active = false
    private var animated = true
    private var restingFrame = CGRect.zero
    private var image: UIImage?
    private var refractionTexture: MTLTexture?
    var refractionRect: (() -> CGRect)?
    var foregroundSource: (() -> InteractiveDiamondComponent.RefractionSource?)?
    var expansionHost: (() -> UIView?)?
    private var expandedView: MTKView?
    var onPressBegan: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?

    var expandedCanvasSize: CGSize {
        let side = max(220, ceil(CGFloat(style.widthPoints) * 3.6))
        return CGSize(width: side, height: side)
    }
    private var appliedHighlightBoost: Float = 0
    private var isHighDynamicRange = false
    private(set) var grip = CGFloat.zero
    private var holding = false
    private var expanded = false
    private var expansion: Expansion?
    private struct Expansion {
        let start: CFTimeInterval
        let from: CGFloat
        let holding: Bool
    }
    private var dragPosition: CGPoint?
    private var dragSamples: [(x: CGFloat, time: CFTimeInterval)] = []
    private var landingFeedback: DispatchWorkItem?
    private let inFlight = DispatchSemaphore(value: 2)
    private lazy var pressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        return gesture
    }()

    init?(diamond: Void) {
        guard let renderer = TelegramDiamondResources.renderer, let queue = TelegramDiamondResources.queue else { return nil }
        self.renderer = renderer
        self.queue = queue
        super.init(frame: .zero, device: renderer.device)
        style.animationMode = .continuous
        style.rotationSpeed = 2 * .pi / 26
        style.swayScale = 1
        style.backgroundStars = false
        style.mainSparkleOnRotation = true
        style.releaseTilt = 2.6
        motion.swayScale = style.swayScale
        motion.mainSparkleOnRotation = true
        motion.releaseTilt = style.releaseTilt
        colorPixelFormat = .bgra8Unorm
        // Keep MSAA/depth ownership outside MetalKit's asynchronously resized buffers.
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        autoResizeDrawable = false
        isPaused = true
        enableSetNeedsDisplay = false
        delegate = self
        addGestureRecognizer(pressGesture)
        isAccessibilityElement = true
        accessibilityLabel = lang("3D Gram Diamond")
        accessibilityHint = lang("Hold to enlarge. Drag to rotate.")
        accessibilityTraits = [.button, .allowsDirectInteraction]
        accessibilityIdentifier = "tokenHero.diamond"
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackChanged), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        expandedView?.removeFromSuperview()
        landingFeedback?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(active: Bool, animated: Bool = true) {
        guard self.active != active || self.animated != animated else { return }
        self.active = active
        self.animated = animated
        if !active || !animated { suspend() }
        playbackChanged()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { suspend() }
        playbackChanged()
    }

    @objc private func playbackChanged() {
        lastTime = nil
        let visible = active && window != nil && UIApplication.shared.applicationState == .active
        let interactive = visible && animated && !UIAccessibility.isReduceMotionEnabled
        if !interactive { suspend() }
        isPaused = !interactive || expandedView != nil
        expandedView?.isPaused = !interactive
        pressGesture.isEnabled = interactive
        isUserInteractionEnabled = interactive
        accessibilityTraits = interactive ? [.button, .allowsDirectInteraction] : [.image]
        accessibilityHint = interactive ? lang("Hold to enlarge. Drag to rotate.") : nil
        if visible && isPaused { draw() }
    }

    @objc private func suspend() {
        landingFeedback?.cancel()
        landingFeedback = nil
        motion.end(at: CACurrentMediaTime(), cancelled: true)
        motion.stopSpin()
        dragPosition = nil
        dragSamples.removeAll(keepingCapacity: true)
        holding = false
        expansion = nil
        grip = 0
        lastTime = nil
        appliedHighlightBoost = 0
        renderTargets.clear()
        updateCanvas()
        isPaused = true
    }

    func setRestingFrame(_ frame: CGRect, width: CGFloat) {
        let changed = restingFrame != frame || style.widthPoints != Float(width)
        restingFrame = frame
        style.widthPoints = Float(width)
        updateCanvas()
        if changed && isPaused { draw() }
    }

    private func updateExpansion(at now: CFTimeInterval) {
        guard let expansion else { return }
        let elapsed = max(0, now - expansion.start)
        if expansion.holding {
            let t = min(1, elapsed / 0.46)
            let u = t * t * (3 - 2 * t)
            let settle = 1 - exp(-5.6 * u) * (cos(6.2 * u) + 5.6 / 6.2 * sin(6.2 * u))
            grip = expansion.from + (1 - expansion.from) * CGFloat(settle)
            if t == 1 { grip = 1; self.expansion = nil }
        } else {
            grip = expansion.from * CGFloat(exp(-4.2 * elapsed) * cos(7 * elapsed))
            if elapsed >= 1.96 { grip = 0; self.expansion = nil }
        }
    }

    func setHolding(_ holding: Bool, at now: CFTimeInterval) {
        guard self.holding != holding else { return }
        updateExpansion(at: now)
        self.holding = holding
        if UIAccessibility.isReduceMotionEnabled {
            expansion = nil
            grip = holding ? 1 : 0
        } else {
            expansion = Expansion(start: now, from: grip, holding: holding)
        }
        updateCanvas()
    }

    private func updateCanvas() {
        let expanded = holding || expansion != nil
        if self.expanded != expanded {
            self.expanded = expanded
            onExpansionChanged?(expanded)
        }
        let size = expanded ? expandedCanvasSize : restingFrame.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: restingFrame.midX - size.width / 2, y: restingFrame.midY - size.height / 2,
            width: size.width, height: size.height)
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        let pixels = CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        if drawableSize != pixels { drawableSize = pixels }
        preferredFramesPerSecond = expanded ? (window?.screen.maximumFramesPerSecond ?? 120) : 60
        updateExpandedView()
        CATransaction.commit()
    }

    private func updateExpandedView() {
        if expanded, expandedView == nil, let host = expansionHost?() {
            let view = MTKView(frame: .zero, device: device)
            view.isOpaque = false
            view.backgroundColor = .clear
            view.clearColor = clearColor
            view.autoResizeDrawable = false
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
            view.delegate = self
            view.isPaused = isPaused
            host.addSubview(view)
            expandedView = view
            // Keep the gesture's view in place while drawing above the navigation title.
            layer.mask = CALayer()
            isPaused = true
        } else if !expanded, let view = expandedView {
            isPaused = view.isPaused
            view.isPaused = true
            view.delegate = nil
            view.removeFromSuperview()
            expandedView = nil
            layer.mask = nil
        }
        if let view = expandedView, let host = view.superview {
            view.frame = convert(bounds, to: host)
            view.contentScaleFactor = contentScaleFactor
            if view.drawableSize != drawableSize { view.drawableSize = drawableSize }
            view.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }

    func snapshotBackground(in window: UIWindow, rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, window.screen.scale)
        format.opaque = false
        let diamondRect = convert(bounds, to: window)
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            // The resting canvas contains only the diamond; exclude its cached Metal pixels.
            context.cgContext.clear(diamondRect)
        }
    }

    private func updateMotion(at now: CFTimeInterval) {
        let dt = Float(lastTime.map { min(max(0, now - $0), 0.05) } ?? 0)
        lastTime = now
        let reduceMotion = !animated || UIAccessibility.isReduceMotionEnabled
        if !reduceMotion { elapsed += dt }
        motion.step(dt: dt, speed: style.rotationSpeed, reduceMotion: reduceMotion, mode: style.animationMode, time: elapsed)
        updateExpansion(at: now)
        updateCanvas()
        let target = 0.4 * Float(min(1, max(0, grip)))
        appliedHighlightBoost += (target - appliedHighlightBoost) * (1 - exp(-dt / 0.25))
        if abs(appliedHighlightBoost - target) < 0.001 { appliedHighlightBoost = target }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard active, window != nil, UIApplication.shared.applicationState == .active,
              bounds.width > 0, bounds.height > 0 else { return }
        updateMotion(at: CACurrentMediaTime())
        // Updating motion can switch surfaces when the expansion settles.
        guard view === (expandedView ?? self) else { return }
        let strength = Float(min(1, max(0, grip)))
        let boost = UIAccessibility.isReduceMotionEnabled ? 0.4 * strength : appliedHighlightBoost
        var hdr = false
        if #available(iOS 17, *) {
            hdr = (window?.screen.potentialEDRHeadroom ?? 1) > 1 && (boost > 0.001 || 0.4 * strength > 0.001)
        }
        let pixelFormat: MTLPixelFormat = hdr ? .rgba16Float : .bgra8Unorm
        if hdr != isHighDynamicRange || view.colorPixelFormat != pixelFormat {
            isHighDynamicRange = hdr
            view.colorPixelFormat = pixelFormat
            if let layer = view.layer as? CAMetalLayer {
                layer.colorspace = hdr ? CGColorSpace(name: CGColorSpace.extendedSRGB) : CGColorSpaceCreateDeviceRGB()
                if #available(iOS 26, *) {
                    layer.contentsHeadroom = hdr ? 2.2 : 1
                    layer.preferredDynamicRange = hdr ? .high : .standard
                } else if #available(iOS 17, *) {
                    layer.wantsExtendedDynamicRangeContent = hdr
                }
            }
        }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable,
              let pass = renderTargets.renderPass(resolving: drawable.texture, sampleCount: renderer.sampleCount),
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let source = expanded ? (foregroundSource?() ?? refractionTexture.map {
            InteractiveDiamondComponent.RefractionSource(texture: $0, uv: SIMD4(0, 0, 1, 1),
                rect: refractionRect?() ?? .zero, preservesColors: true)
        }) : nil
        let texture = drawable.texture
        let renderSize = CGSize(width: texture.width, height: texture.height)
        let pixelsPerPoint = Float(texture.width) / Float(bounds.width)
        // All heroes use the receive diamond’s threefold hold expansion.
        renderer.encode(encoder: encoder, size: renderSize, time: elapsed, starBursts: [], starOffset: .zero,
            motion: motion, style: style, grow: Float(1 + 2 * grip),
            pixelsPerPoint: pixelsPerPoint, reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled,
            lightBackground: traitCollection.userInterfaceStyle != .dark, refractionSource: source,
            refractionStrength: strength, highlightBoost: hdr && texture.pixelFormat == .rgba16Float ? boost : 0,
            colorPixelFormat: texture.pixelFormat)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        command.commit()
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        let position = gesture.location(in: self)
        // The canvas changes size during expansion; sample in the parent's fixed coordinates.
        let point = convert(position, to: superview)
        var now = CACurrentMediaTime()
        updateMotion(at: now)
        switch gesture.state {
        case .began:
            onPressBegan?()
            // Snapshot preparation must not consume the scale-up animation's duration.
            now = CACurrentMediaTime()
            landingFeedback?.cancel()
            TelegramDiamondResources.haptic.prepare()
            dragPosition = point
            dragSamples = [(point.x, now)]
            motion.begin(at: now)
            setHolding(true, at: now)
        case .changed, .ended:
            guard let previous = dragPosition, motion.isDragging else { return }
            let releasePower = grip
            let translation = CGPoint(x: point.x - previous.x, y: point.y - previous.y)
            dragSamples.append((point.x, now))
            while dragSamples.count > 2 && dragSamples[0].time < now - 0.08 { dragSamples.removeFirst() }
            let sample = dragSamples[0]
            let interval = CGFloat(max(now - sample.time, 1 / 240.0))
            let velocity = (point.x - sample.x) / interval
            dragPosition = gesture.state == .ended ? nil : point
            if translation != .zero {
                motion.drag(dx: Float(translation.x), dy: Float(translation.y), scale: 220, at: now)
            }
            if gesture.state == .ended {
                dragSamples.removeAll(keepingCapacity: true)
                motion.step(dt: 0, speed: style.rotationSpeed, reduceMotion: UIAccessibility.isReduceMotionEnabled, time: elapsed)
                motion.end(at: now)
                if abs(velocity) > 600 && !UIAccessibility.isReduceMotionEnabled {
                    motion.fling(direction: velocity < 0 ? -1 : 1, impulse: 3 * 6.5)
                }
                setHolding(false, at: now)
                scheduleLanding(power: releasePower)
            }
        case .cancelled, .failed:
            landingFeedback?.cancel()
            dragPosition = nil
            dragSamples.removeAll(keepingCapacity: true)
            motion.end(at: now, cancelled: true)
            setHolding(false, at: now)
        default: break
        }
        motion.step(dt: 0, speed: style.rotationSpeed, reduceMotion: UIAccessibility.isReduceMotionEnabled, time: elapsed)
        updateCanvas()
        if isPaused { draw() }
    }

    private func scheduleLanding(power: CGFloat) {
        guard power > 0.2, !holding else { return }
        let feedback = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil, self.active, !self.holding, UIApplication.shared.applicationState == .active else { return }
            TelegramDiamondResources.haptic.impactOccurred(intensity: 0.35 + 0.4 * min(1, power))
            TelegramDiamondResources.haptic.prepare()
        }
        landingFeedback = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: feedback)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        CGRect(x: bounds.midX - 32, y: bounds.midY - 32, width: 64, height: 64).contains(point)
    }

    override func accessibilityActivate() -> Bool {
        guard active, isUserInteractionEnabled, window != nil, !holding else { return false }
        let now = CACurrentMediaTime()
        updateMotion(at: now)
        onPressBegan?()
        let start = CACurrentMediaTime()
        motion.begin(at: start)
        setHolding(true, at: start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.holding else { return }
            let now = CACurrentMediaTime()
            self.updateMotion(at: now)
            self.motion.end(at: now)
            self.setHolding(false, at: now)
            if self.isPaused { self.draw() }
        }
        if isPaused { draw() }
        return true
    }

    func setRefractionImage(_ image: UIImage?) {
        guard self.image !== image else { return }
        self.image = image
        refractionTexture = image.flatMap { Self.qrMaskTexture(image: $0, device: renderer.device) }
    }

    static func qrMaskTexture(image: UIImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            let bytes = context.data else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                let alpha = 255 - pixels[offset + 2]
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = alpha
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Wallet receive QR refraction"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }
}
