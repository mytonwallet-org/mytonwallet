import Metal
import QuartzCore
import UIKit

@MainActor private enum AgentEdgeGlowResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let pipeline: MTLRenderPipelineState? = {
        guard let device, let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "agentEdgeGlowVertex"),
              let fragment = library.makeFunction(name: "agentEdgeGlowFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    static let queue = device?.makeCommandQueue()
}

/// The glow that runs around the display's edge while the Agent thinks: a blue and a purple light travelling
/// clockwise, each side in the same time, fading inward over a few points, as in Apple Intelligence.
///
/// Place this view behind glass controls so their backdrop includes and refracts the moving light.
public final class AgentEdgeGlowView: UIView {
    public private(set) var isGlowing = false
    private var overlay: AgentEdgeGlowOverlayView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateOverlay()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        overlay?.updateFrame()
    }

    public func setGlowing(_ isGlowing: Bool) {
        guard self.isGlowing != isGlowing else { return }
        self.isGlowing = isGlowing
        updateOverlay()
    }

    private func updateOverlay() {
        if let overlay, overlay.superview == nil || overlay.window !== window {
            overlay.hide()
            self.overlay = nil
        }
        guard isGlowing else {
            overlay?.hide()
            return
        }
        guard let window, AgentEdgeGlowResources.pipeline != nil else { return }
        let overlay = self.overlay ?? makeOverlay(in: window)
        overlay.show()
    }

    private func makeOverlay(in window: UIWindow) -> AgentEdgeGlowOverlayView {
        let overlay = AgentEdgeGlowOverlayView(owner: self)
        addSubview(overlay)
        overlay.updateFrame()
        overlay.setNeedsLayout()
        self.overlay = overlay
        return overlay
    }
}

/// The radius of the display's rounded corners, from a table of iPhone panels keyed by native resolution
@MainActor public enum AgentDisplayCornerRadius {
    private struct Panel {
        let nativeSize: CGSize
        /// Width in points at the standard Display Zoom setting
        let pointWidth: CGFloat
        /// Corner radius in points at the standard Display Zoom setting
        let radius: CGFloat
    }

    private static let panels: [Panel] = [
        // iPhone X, XS, 11 Pro
        Panel(nativeSize: CGSize(width: 1125, height: 2436), pointWidth: 375, radius: 39),
        // iPhone XS Max, 11 Pro Max
        Panel(nativeSize: CGSize(width: 1242, height: 2688), pointWidth: 414, radius: 39),
        // iPhone XR, 11
        Panel(nativeSize: CGSize(width: 828, height: 1792), pointWidth: 414, radius: 41.5),
        // iPhone 12 mini, 13 mini
        Panel(nativeSize: CGSize(width: 1080, height: 2340), pointWidth: 375, radius: 44),
        // iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e
        Panel(nativeSize: CGSize(width: 1170, height: 2532), pointWidth: 390, radius: 47.33),
        // iPhone 12 Pro Max, 13 Pro Max, 14 Plus
        Panel(nativeSize: CGSize(width: 1284, height: 2778), pointWidth: 428, radius: 53.33),
        // iPhone 14 Pro, 15, 15 Pro, 16
        Panel(nativeSize: CGSize(width: 1179, height: 2556), pointWidth: 393, radius: 55),
        // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
        Panel(nativeSize: CGSize(width: 1290, height: 2796), pointWidth: 430, radius: 55),
        // iPhone 16 Pro, 17, 17 Pro
        Panel(nativeSize: CGSize(width: 1206, height: 2622), pointWidth: 402, radius: 62),
        // iPhone 16 Pro Max, 17 Pro Max
        Panel(nativeSize: CGSize(width: 1320, height: 2868), pointWidth: 440, radius: 62),
        // iPhone Air
        Panel(nativeSize: CGSize(width: 1260, height: 2736), pointWidth: 420, radius: 62),
    ]

    public static func getRadius(for window: UIWindow) -> CGFloat {
        let screen = window.windowScene?.screen ?? window.screen
        let native = screen.nativeBounds.size
        let nativeSize = CGSize(width: min(native.width, native.height), height: max(native.width, native.height))
        let windowSize = window.bounds.size
        let screenSize = screen.bounds.size
        let isFillingScreen = abs(windowSize.width - screenSize.width) < 1 && abs(windowSize.height - screenSize.height) < 1
        let hasHomeIndicator = window.safeAreaInsets.bottom > 0
        guard isFillingScreen else {
            // A window in iPad multitasking has its own small rounding
            return hasHomeIndicator ? 10 : 0
        }
        if let panel = panels.first(where: { $0.nativeSize == nativeSize }), screen.nativeScale > 0 {
            // The physical rounding is fixed; Display Zoom changes how many pixels a point covers
            return panel.radius * (panel.nativeSize.width / panel.pointWidth) / screen.nativeScale
        }
        // iPads round their corners by model, the latest iPad Pro much more than earlier ones: the system knows by how
        // much, as it does for the iPhones above
        if let radius = getSystemRadius(of: screen) {
            return radius
        }
        if window.traitCollection.userInterfaceIdiom == .pad {
            return hasHomeIndicator ? 18 : 0
        }
        return hasHomeIndicator ? 55 : 0
    }

    private static func getSystemRadius(of screen: UIScreen) -> CGFloat? {
        let key = PrivateAPI.displayCornerRadius
        guard screen.responds(to: key.selector),
              let radius = (screen.value(forKey: key.string) as? NSNumber)?.doubleValue,
              radius > 0 else { return nil }
        return CGFloat(radius)
    }
}

/// Passthrough overlay over a whole window. It renders the glow only into four strips along the edges, so
/// the rest of the window is never recomposited because of it.
@MainActor
private final class AgentEdgeGlowOverlayView: UIView {
    /// Matches `AgentEdgeGlowUniforms` in `AgentEdgeGlow.metal`: three `float4`, 48 bytes
    private struct Uniforms {
        /// Window size and the strip's origin in the window, in points
        var frame: SIMD4<Float>
        /// Drawable pixels per point, display corner radius, time, opacity
        var parameters: SIMD4<Float>
        /// Dark appearance; the rest is reserved
        var appearance: SIMD4<Float>
    }

    /// One loop of the lights, as in the shader
    private static let loopDuration: CFTimeInterval = 2.667
    /// The glow comes in slowly and goes a little faster, each eased at both ends
    private static let fadeInDuration: CFTimeInterval = 0.7
    private static let fadeOutDuration: CFTimeInterval = 0.4
    /// The shader draws up to 30 pt in from the rounded edge
    private static let glowDepth: CGFloat = 30

    private weak var owner: UIView?
    private let strips: [AgentEdgeGlowStripView]
    private lazy var clock = GlassMotionClock(
        frameRateRange: CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    ) { [weak self] _ in self?.tick() }
    private let startTime = CACurrentMediaTime()
    private var fadeStart: CFTimeInterval = 0
    private var fadeFrom: Float = 0
    private var fadeTarget: Float = 0
    private var cornerRadius: CGFloat = 0
    private let inFlight = DispatchSemaphore(value: 2)

    init(owner: UIView) {
        self.owner = owner
        strips = (0..<4).map { _ in AgentEdgeGlowStripView() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        for strip in strips {
            addSubview(strip)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func updateFrame() {
        guard let owner, let window = owner.window else { return }
        let pane = owner.convert(owner.bounds, to: window).intersection(window.bounds)
        guard !pane.isEmpty else { return }
        let windowFrame = abs(pane.width - window.bounds.width) < 1 ? window.bounds : pane
        let nextFrame = owner.convert(windowFrame, from: window)
        if frame != nextFrame {
            frame = nextFrame
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    /// Fades in from the current opacity
    func show() {
        fade(to: 1)
    }

    /// Fades out from the current opacity and leaves the window
    func hide() {
        fade(to: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fillsWindow = window.map { abs(frame.width - $0.bounds.width) < 1 } ?? false
        cornerRadius = fillsWindow ? window.map { AgentDisplayCornerRadius.getRadius(for: $0) } ?? 0 : 20
        // Deep enough that the strips cover the band also where it curves in along a rounded corner: the band's
        // inner edge is a quarter circle of radius `cornerRadius - glowDepth`, reaching furthest on the diagonal
        let innerRadius: CGFloat = max(0, cornerRadius - Self.glowDepth)
        let cornerDepth: CGFloat = cornerRadius - innerRadius * 0.7071
        let depth: CGFloat = ceil(max(Self.glowDepth, cornerDepth)) + 2
        let width = bounds.width
        let height = bounds.height
        let sideHeight = max(0, height - 2 * depth)
        let frames = [
            CGRect(x: 0, y: 0, width: width, height: min(depth, height)),
            CGRect(x: max(0, width - depth), y: depth, width: min(depth, width), height: sideHeight),
            CGRect(x: 0, y: max(0, height - depth), width: width, height: min(depth, height)),
            CGRect(x: 0, y: depth, width: min(depth, width), height: sideHeight),
        ]
        let scale = min(2, window?.screen.scale ?? traitCollection.displayScale)
        for (strip, frame) in zip(strips, frames) {
            strip.frame = frame
            strip.metalLayer?.contentsScale = scale
            strip.metalLayer?.drawableSize = CGSize(
                width: max(1, ceil(frame.width * scale)),
                height: max(1, ceil(frame.height * scale))
            )
        }
        if !clock.isRunning { render() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        handlePlaybackChange()
    }

    private func fade(to target: Float) {
        let now = CACurrentMediaTime()
        fadeFrom = getOpacity(at: now)
        fadeTarget = target
        fadeStart = now
        if target == 0 && fadeFrom <= 0 {
            finishHiding()
            return
        }
        handlePlaybackChange()
    }

    private func finishHiding() {
        clock.stop()
        removeFromSuperview()
    }

    /// Fade at a constant rate, so reversing it midway takes only as long as the distance back
    private func getOpacity(at time: CFTimeInterval) -> Float {
        let distance = abs(fadeTarget - fadeFrom)
        guard distance > 0 else { return fadeTarget }
        let duration = fadeTarget > fadeFrom ? Self.fadeInDuration : Self.fadeOutDuration
        let progress = Float(max(0, time - fadeStart) / duration) / distance
        return fadeFrom + (fadeTarget - fadeFrom) * min(1, progress)
    }

    /// The opacity drawn: the fade eased at both ends, so the glow neither pops in nor cuts off
    private func getShownOpacity(at time: CFTimeInterval) -> Float {
        let value = min(1, max(0, getOpacity(at: time)))
        return value * value * (3 - 2 * value)
    }

    @objc private func handlePlaybackChange() {
        guard window != nil else {
            clock.stop()
            return
        }
        let currentOpacity = getOpacity(at: CACurrentMediaTime())
        let isVisible = fadeTarget > 0 || currentOpacity > 0
        let isFading = currentOpacity != fadeTarget
        // With Reduce Motion the lights stand still, so frames are only needed while the glow fades
        let shouldRun = isVisible && UIApplication.shared.applicationState != .background
            && (isFading || !UIAccessibility.isReduceMotionEnabled)
        if shouldRun {
            clock.start()
        } else {
            clock.pause()
            if isVisible { render() }
        }
    }

    private func tick() {
        updateFrame()
        let currentOpacity = getOpacity(at: CACurrentMediaTime())
        render()
        guard currentOpacity == fadeTarget else { return }
        if fadeTarget == 0 {
            finishHiding()
        } else if UIAccessibility.isReduceMotionEnabled {
            // The still glow keeps its last frame without further frames
            handlePlaybackChange()
        }
    }

    private func render() {
        // Work submitted to the GPU from the background is rejected
        guard window != nil, UIApplication.shared.applicationState != .background,
              let pipeline = AgentEdgeGlowResources.pipeline, let queue = AgentEdgeGlowResources.queue,
              bounds.width > 0, bounds.height > 0,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let command = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let now = CACurrentMediaTime()
        let currentOpacity = getShownOpacity(at: now)
        let time = UIAccessibility.isReduceMotionEnabled
            ? 0
            : (now - startTime).truncatingRemainder(dividingBy: Self.loopDuration)
        let style = owner?.traitCollection.userInterfaceStyle ?? traitCollection.userInterfaceStyle
        for strip in strips {
            guard let metalLayer = strip.metalLayer, strip.bounds.width > 0, strip.bounds.height > 0,
                  let drawable = metalLayer.nextDrawable() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { continue }
            var uniforms = Uniforms(
                frame: SIMD4(
                    Float(bounds.width),
                    Float(bounds.height),
                    Float(strip.frame.minX),
                    Float(strip.frame.minY)
                ),
                parameters: SIMD4(
                    Float(drawable.texture.width) / Float(strip.bounds.width),
                    Float(cornerRadius),
                    Float(time),
                    currentOpacity
                ),
                appearance: SIMD4(style == .dark ? 1 : 0, 0, 0, 0)
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.present(drawable)
        }
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        command.commit()
    }
}

/// One edge strip of the overlay, backed by its own Metal layer
private final class AgentEdgeGlowStripView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        if let metalLayer {
            metalLayer.device = AgentEdgeGlowResources.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = false
            // The colours are sRGB, as measured from the reference
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
