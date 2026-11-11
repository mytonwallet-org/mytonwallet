import Metal
import QuartzCore
import UIKit

@MainActor private enum AgentFieldGlowResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let lightsPipeline = makePipeline(fragment: "agentFieldGlowFragment")
    static let rimPipeline = makePipeline(fragment: "agentFieldRimFragment")
    static let queue = device?.makeCommandQueue()

    private static func makePipeline(fragment name: String) -> MTLRenderPipelineState? {
        guard let device, let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "agentFieldGlowVertex"),
              let fragment = library.makeFunction(name: name) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}

/// Telegram's listening glow of a text field, in two parts: the lights inside the field and its glowing rim. Its
/// frames run only while it shows and moves; with Reduce Motion its lights stand still.
public final class AgentFieldGlowView: UIView {
    public enum Part {
        /// The lights inside the field, as Android's `AgentFieldGlowView` draws them: a soft light in the accent colour
        /// along the field's edge, brightest at the bottom and the leading side, with lights drifting along the bottom,
        /// through the field and up and down the leading side. They show at half the strength of Android's reference
        /// shader and move twice as fast. The view lies over the field, which clips them to its rounded shape.
        case lights
        /// The field's border giving off light: a thin, almost white core line, a bloom in the accent colour spilling
        /// out beyond the field and a softer haze inside it, brightest at the bottom and the leading side, with bright
        /// stretches running along it. The view reaches `rimMargin` beyond the field on every side, over its edge.
        case rim
    }

    /// How far the rim's view reaches beyond the field on every side, for the bloom
    public static let rimMargin: CGFloat = 28

    /// Matches `AgentFieldGlowUniforms` in AgentFieldGlow.metal: three float4, 48 bytes
    private struct Uniforms {
        /// xy: the field's size, points; z: drawable pixels per point; w: corner radius, points
        var geometry: SIMD4<Float>
        /// x: time, seconds; y: opacity; z: the leading side, 0 for the left and 1 for the right; w: how far the
        /// view reaches beyond the field on every side, points
        var motion: SIMD4<Float>
        /// rgb: the accent colour
        var tint: SIMD4<Float>
    }

    public override static var layerClass: AnyClass { CAMetalLayer.self }

    public let part: Part
    public private(set) var isGlowing = false
    /// The field's corner radius
    public var cornerRadius: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    /// The field the rim lies over. The rim takes the field's frame as it shows on every frame it draws, through the
    /// field's own animations and its host's, so it never stands apart from the field or doubles its edge.
    public weak var field: UIView?

    private lazy var clock = GlassMotionClock(
        frameRateRange: CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    ) { [weak self] _ in self?.tick() }
    private var glowStart: CFTimeInterval = 0
    private var fadeStart: CFTimeInterval = 0
    private var fadeFrom: Float = 0
    private var fadeTarget: Float = 0
    private let inFlight = DispatchSemaphore(value: 2)

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    public init(part: Part) {
        self.part = part
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isOpaque = false
        backgroundColor = .clear
        isHidden = true
        layer.masksToBounds = part == .lights
        layer.cornerCurve = .continuous
        if let metalLayer {
            metalLayer.device = AgentFieldGlowResources.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = false
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        let center = NotificationCenter.default
        // The app is still in the background as it is about to enter the foreground, so the glow goes on once it is
        // active again
        for name in [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.didBecomeActiveNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
        ] {
            center.addObserver(self, selector: #selector(updatePlayback), name: name, object: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fades the glow in or out from where it is, or shows or hides it at once
    public func setGlowing(_ isGlowing: Bool, animated: Bool) {
        guard isGlowing != self.isGlowing else { return }
        self.isGlowing = isGlowing
        let now = CACurrentMediaTime()
        let target: Float = isGlowing ? 1 : 0
        let opacity = getOpacity(at: now)
        if isGlowing && opacity <= 0 {
            glowStart = now
        }
        fadeFrom = animated ? opacity : target
        fadeTarget = target
        fadeStart = now
        updatePlayback()
    }

    /// The field's size and corner radius, inside the view's margin
    private var fieldShape: (size: CGSize, radius: CGFloat) {
        let size = bounds.insetBy(dx: margin, dy: margin).size
        return (size, min(cornerRadius, size.height / 2))
    }

    private var margin: CGFloat {
        part == .rim ? Self.rimMargin : 0
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = part == .lights ? fieldShape.radius : 0
        let scale = min(2, window?.screen.scale ?? traitCollection.displayScale)
        metalLayer?.contentsScale = scale
        metalLayer?.drawableSize = CGSize(
            width: max(1, ceil(bounds.width * scale)),
            height: max(1, ceil(bounds.height * scale))
        )
        if !isHidden, !clock.isRunning { render() }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        if !isHidden, !clock.isRunning { render() }
    }

    /// In a window on a screen, whose drawables come back once shown, and in the foreground, as work submitted to the
    /// GPU from the background is rejected
    private var canRender: Bool {
        window?.windowScene != nil && UIApplication.shared.applicationState != .background
    }

    /// Fades at a constant rate, so reversing a fade midway takes only as long as the distance back
    private func getOpacity(at time: CFTimeInterval) -> Float {
        let distance = abs(fadeTarget - fadeFrom)
        guard distance > 0 else { return fadeTarget }
        let duration = fadeTarget > fadeFrom ? Self.fadeInDuration : Self.fadeOutDuration
        let progress = Float(max(0, time - fadeStart) / duration) / distance
        return fadeFrom + (fadeTarget - fadeFrom) * min(1, progress)
    }

    @objc private func updatePlayback() {
        let opacity = getOpacity(at: CACurrentMediaTime())
        let isVisible = fadeTarget > 0 || opacity > 0
        isHidden = !isVisible
        // With Reduce Motion the lights stand still, so frames are only needed while the glow fades
        let shouldRun = isVisible && canRender && (opacity != fadeTarget || !UIAccessibility.isReduceMotionEnabled)
        if shouldRun {
            clock.start()
        } else {
            clock.pause()
            if isVisible { render() }
        }
    }

    private func tick() {
        followField()
        render()
        let opacity = getOpacity(at: CACurrentMediaTime())
        if opacity == fadeTarget && (fadeTarget == 0 || UIAccessibility.isReduceMotionEnabled) {
            updatePlayback()
        }
    }

    /// Lays the rim over `field` where the field shows now, `rimMargin` beyond it on every side
    private func followField() {
        guard part == .rim, let field, let superview, field.window != nil, field.window === window else { return }
        let frame = field.convertAsShown(to: superview).insetBy(dx: -Self.rimMargin, dy: -Self.rimMargin)
        guard frame != self.frame || layer.animationKeys()?.isEmpty == false else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A frame animated by a layout elsewhere would stand apart from the field it follows
        layer.removeAllAnimations()
        self.frame = frame
        CATransaction.commit()
        layoutIfNeeded()
    }

    private func render() {
        let pipeline = part == .rim ? AgentFieldGlowResources.rimPipeline : AgentFieldGlowResources.lightsPipeline
        let field = fieldShape
        guard canRender, let pipeline, let queue = AgentFieldGlowResources.queue,
              let metalLayer, field.size.width > 0, field.size.height > 0,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let command = queue.makeCommandBuffer(), let drawable = metalLayer.nextDrawable() else {
            inFlight.signal()
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let now = CACurrentMediaTime()
        let value = min(1, max(0, getOpacity(at: now)))
        // Eased at both ends, so the glow neither pops in nor cuts off
        let isLights = part == .lights
        let opacity = value * value * (3 - 2 * value) * (isLights ? Self.lightsStrength : 1)
        let speed = isLights ? Self.lightsSpeed : 1
        let time = UIAccessibility.isReduceMotionEnabled ? 0 : Float(now - glowStart) * speed
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        let tint = (tintColor ?? .systemBlue).resolvedColor(with: traitCollection)
        _ = tint.getRed(&red, green: &green, blue: &blue, alpha: nil)
        var uniforms = Uniforms(
            geometry: SIMD4(
                Float(field.size.width),
                Float(field.size.height),
                Float(drawable.texture.width) / Float(bounds.width),
                Float(field.radius)
            ),
            motion: SIMD4(time, opacity, effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 : 0, Float(margin)),
            tint: SIMD4(
                Float(min(1, max(0, red))),
                Float(min(1, max(0, green))),
                Float(min(1, max(0, blue))),
                1
            )
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        command.commit()
    }

    private static let fadeInDuration: CFTimeInterval = 0.3
    /// Quick, so the glow is gone from the field before what follows, such as the push into a chat, moves it
    private static let fadeOutDuration: CFTimeInterval = 0.18
    /// Half the opacity of Android's reference shader
    private static let lightsStrength: Float = 0.5
    /// Twice the pace of Android's reference shader
    private static let lightsSpeed: Float = 2
}
