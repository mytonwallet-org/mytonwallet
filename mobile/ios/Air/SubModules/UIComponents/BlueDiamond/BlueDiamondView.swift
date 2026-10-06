import Combine
@preconcurrency import Metal
import MetalKit
import SwiftUI
import WalletCore

public struct BlueDiamondView: View {
    @ObservedObject private var environment = CardBackgroundAnimationEnvironment.shared
    @State private var visible = false

    public init() {}

    public var body: some View {
        BlueDiamondRepresentable(
            active: visible && environment.applicationActive,
            animated: environment.animationsEnabled && !environment.lowPowerMode && !environment.reduceMotion
        )
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

private struct BlueDiamondRepresentable: UIViewRepresentable {
    var active: Bool
    var animated: Bool

    func makeUIView(context: Context) -> BlueDiamondContainerView { BlueDiamondContainerView() }

    func updateUIView(_ view: BlueDiamondContainerView, context: Context) {
        view.configure(active: active, animated: animated)
    }

    static func dismantleUIView(_ view: BlueDiamondContainerView, coordinator: ()) {
        view.configure(active: false, animated: false)
    }
}

private final class BlueDiamondContainerView: UIView {
    private let preview = UIImageView()
    private var renderer: BlueDiamondMetalView?
    private var suspension: AnyCancellable?

    init() {
        super.init(frame: .zero)
        if let url = Bundle.module.url(forResource: "preview", withExtension: "png", subdirectory: "BlueDiamond") {
            preview.image = UIImage(contentsOfFile: url.path)
        }
        preview.contentMode = .scaleAspectFit
        addSubview(preview)
        if let scene = BlueDiamondScene.shared {
            let renderer = BlueDiamondMetalView(scene: scene)
            self.renderer = renderer
            addSubview(renderer)
            renderer.onFirstFrame = { [weak self] in self?.preview.isHidden = true }
            renderer.onFailure = { [weak self] in
                self?.preview.isHidden = false
                self?.renderer?.removeFromSuperview()
                self?.renderer = nil
            }
        }
        suspension = CardBackgroundAnimationEnvironment.shared.willSuspend.sink { [weak self] in
            self?.renderer?.configure(active: false, animated: false)
        }
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
        renderer?.frame = bounds
    }

    func configure(active: Bool, animated: Bool) {
        renderer?.configure(active: active, animated: animated)
    }
}

private final class BlueDiamondMetalView: MTKView, MTKViewDelegate {
    var onFirstFrame: (() -> Void)?
    var onFailure: (() -> Void)?
    private let scene: BlueDiamondScene
    private let inFlight = DispatchSemaphore(value: 2)
    private var motion = BlueDiamondMotion()
    private var time: Float = 0
    private var previousTime: CFTimeInterval?
    private var previousAngles: SIMD2<Float>?
    private var active = false
    private var animated = false
    private var failed = false
    private var revealed = false
    private var touchOrigin: CGPoint?
    private var lastTouch: CGPoint?
    private var dragged = false
    private lazy var touchGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTouch(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        return gesture
    }()

    init(scene: BlueDiamondScene) {
        self.scene = scene
        super.init(frame: .zero, device: scene.device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = scene.sampleCount
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        backgroundColor = .clear
        autoResizeDrawable = false
        preferredFramesPerSecond = 60
        isPaused = true
        enableSetNeedsDisplay = false
        alpha = 0
        delegate = self
        addGestureRecognizer(touchGesture)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(active: Bool, animated: Bool) {
        guard self.active != active || self.animated != animated else { return }
        self.active = active
        self.animated = animated
        previousTime = nil
        previousAngles = nil
        if !active || !animated { cancelTouch() }
        updatePlayback()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        previousTime = nil
        previousAngles = nil
        if window == nil { cancelTouch() }
        updatePlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        let size = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        if drawableSize != size {
            drawableSize = size
            if isPaused { draw() }
        }
    }

    private func updatePlayback() {
        let visible = active && window != nil && !failed
        isPaused = !visible || !animated
        isUserInteractionEnabled = visible && animated
        touchGesture.isEnabled = visible && animated
        if visible && isPaused { draw() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard active, !failed, window != nil, UIApplication.shared.applicationState == .active,
              drawableSize.width > 0, drawableSize.height > 0 else { return }
        let now = CACurrentMediaTime()
        let elapsed: CFTimeInterval = previousTime.map { now - $0 } ?? (1.0 / 60.0)
        let delta = Float(min(0.1, max(0, elapsed)))
        previousTime = now
        if animated {
            time += delta
            motion.update(time: time)
        }
        let angles = SIMD2(motion.yaw, motion.pitch)
        let change = angles - (previousAngles ?? angles)
        let speed = delta > 0 ? hypot(atan2(sin(change.x), cos(change.x)), change.y) / delta : 0
        previousAngles = angles
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = scene.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        var uniforms = scene.uniforms(size: drawableSize, time: time, yaw: motion.yaw, pitch: motion.pitch, speed: speed, scale: motion.scale)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BlueDiamondScene.Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlueDiamondScene.Uniforms>.stride, index: 1)
        encoder.setFragmentBuffer(scene.planes, offset: 0, index: 2)
        encoder.setRenderPipelineState(scene.diamondPipeline)
        encoder.setDepthStencilState(scene.depth)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(scene.diamond.buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: scene.diamond.count)
        encoder.setRenderPipelineState(scene.sparklePipeline)
        encoder.setDepthStencilState(scene.noDepth)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(scene.anchors, offset: 0, index: 2)
        var baseInstance: UInt32 = 0
        encoder.setVertexBytes(&baseInstance, length: 4, index: 3)
        encoder.setVertexBuffer(scene.mainSparkle.buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: scene.mainSparkle.count)
        baseInstance = 1
        encoder.setVertexBytes(&baseInstance, length: 4, index: 3)
        encoder.setVertexBuffer(scene.smallSparkles.buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: scene.smallSparkles.count, instanceCount: 7)
        encoder.endEncoding()
        command.present(drawable)
        let needsReveal = !revealed
        command.addCompletedHandler { [weak self, inFlight] command in
            inFlight.signal()
            let succeeded = command.status == .completed
            if needsReveal || !succeeded {
                Task { @MainActor [weak self] in self?.completedFrame(succeeded: succeeded) }
            }
        }
        command.commit()
    }

    private func completedFrame(succeeded: Bool) {
        if !succeeded {
            failed = true
            isPaused = true
            onFailure?()
        } else if !revealed {
            revealed = true
            alpha = 1
            onFirstFrame?()
        }
    }

    // Recognize immediately so dragging the diamond does not scroll its transaction sheet.
    @objc private func handleTouch(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            touchOrigin = point
            lastTouch = point
            dragged = false
            motion.press()
        case .changed:
            guard let lastTouch, let touchOrigin else { return }
            if hypot(point.x - touchOrigin.x, point.y - touchOrigin.y) > 8 { dragged = true }
            guard dragged else { return }
            // Match the reference's rotation per device pixel, independently of render resolution.
            let scale = window?.screen.scale ?? traitCollection.displayScale
            motion.drag(dx: Float((point.x - lastTouch.x) * scale), dy: Float((point.y - lastTouch.y) * scale))
            self.lastTouch = point
        case .ended:
            guard touchOrigin != nil else { return }
            let tap = SIMD2(Float((0.5 - point.x / max(1, bounds.width)) * 2), Float((0.5 - point.y / max(1, bounds.height)) * 2))
            motion.release(time: time, tap: dragged ? nil : tap)
            touchOrigin = nil
            lastTouch = nil
        case .cancelled, .failed:
            cancelTouch()
        default:
            break
        }
    }

    private func cancelTouch() {
        motion.cancelInteraction(time: time)
        touchOrigin = nil
        lastTouch = nil
    }
}
