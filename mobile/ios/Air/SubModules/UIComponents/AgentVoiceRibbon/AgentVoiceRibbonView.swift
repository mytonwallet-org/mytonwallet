import Metal
import QuartzCore
import UIKit

@MainActor private enum AgentVoiceRibbonResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let pipeline: MTLRenderPipelineState? = {
        guard let device, let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "agentVoiceRibbonVertex"),
              let fragment = library.makeFunction(name: "agentVoiceRibbonFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    static let queue = device?.makeCommandQueue()
}

/// A hands-free recording's voice inside the text field: a thread of light the voice spins out of the stop button,
/// whose strands braid and glint on their crests. It runs frames only while it shows, in
/// the foreground; with Reduce Motion it stands still and only its brightness follows the voice.
public final class AgentVoiceRibbonView: UIView {
    public override static var layerClass: AnyClass { CAMetalLayer.self }

    /// From the view's leading edge to the stop button's centre, which the thread comes out of
    public var stopCenter: CGFloat {
        get { CGFloat(model.stopCenter) }
        set {
            model.stopCenter = Float(newValue)
            if !isHidden, !clock.isRunning { render() }
        }
    }

    private var model = AgentVoiceRibbonModel()
    private var rawLevel: Float = 0
    private var lastFrameTime: CFTimeInterval?
    private lazy var clock = GlassMotionClock(
        frameRateRange: CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    ) { [weak self] _ in self?.tick() }
    private let inFlight = DispatchSemaphore(value: 2)
    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isOpaque = false
        backgroundColor = .clear
        isHidden = true
        if let metalLayer {
            metalLayer.device = AgentVoiceRibbonResources.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.isOpaque = false
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        model.isReduceMotion = UIAccessibility.isReduceMotionEnabled
        let center = NotificationCenter.default
        // The app is still in the background as it is about to enter the foreground, so the thread goes on once it is
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

    /// Spins the thread out of the stop button
    public func start() {
        model.start()
        updatePlayback()
    }

    /// Gathers the thread back into the stop button, as the recording goes to be recognized
    public func stop() {
        model.stop()
        updatePlayback()
    }

    /// Drains the thread of colour as it fades
    public func cancel() {
        model.cancel()
        updatePlayback()
    }

    /// Slides the thread into Send
    public func send() {
        model.send()
        updatePlayback()
    }

    /// The voice's peak since the last frame, from 0 to 1
    public func setLevel(_ level: Float) {
        rawLevel = min(1, max(0, level))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
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

    @objc private func updatePlayback() {
        model.isReduceMotion = UIAccessibility.isReduceMotionEnabled
        isHidden = model.isFinished
        if !isHidden && canRender {
            clock.start()
        } else {
            clock.pause()
            lastFrameTime = nil
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // A frame after a pause takes no more than a frame's time, so the thread doesn't jump ahead
        let deltaTime = lastFrameTime.map { min(Float(now - $0), 0.05) } ?? 0
        lastFrameTime = now
        model.step(deltaTime: deltaTime, rawLevel: rawLevel)
        render()
        if model.isFinished { updatePlayback() }
    }

    private func render() {
        guard canRender, let pipeline = AgentVoiceRibbonResources.pipeline, let queue = AgentVoiceRibbonResources.queue,
              let metalLayer, bounds.width > 0, bounds.height > 0,
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
        let accent = (tintColor ?? .systemBlue).resolvedColor(with: traitCollection)
        var uniforms = model.makeUniforms(
            size: bounds.size,
            scale: Float(drawable.texture.width) / Float(bounds.width),
            accent: accent,
            isDark: traitCollection.userInterfaceStyle == .dark,
            isRightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AgentVoiceRibbonUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        command.commit()
    }
}
