import MetalKit
import UIKit
import WalletContext

@MainActor private enum SpinningTopResources {
    static let renderer = MTLCreateSystemDefaultDevice().flatMap { SpinningTopRenderer(device: $0) }
    static let queue = renderer?.device.makeCommandQueue()
    static let haptic = UIImpactFeedbackGenerator(style: .light)
}

private enum SpinningTopMetrics {
    /// Where the expanded top can reach around its box's centre, in its model units (y up), however it is tilted: the
    /// rim swings below the point as the top tips toward the viewer, the leaning stem reaches up and aside. Its canvas
    /// covers this with a margin for the springy overshoot.
    static let expandedReach = (minX: CGFloat(-1.22), maxX: CGFloat(0.96), minY: CGFloat(-1.52), maxY: CGFloat(0.82))
    static let expandedReachMargin: CGFloat = 0.1
    static let minimumExpandedCanvasSide: CGFloat = 160
    /// The held top's body across, around its box's centre in its model units: the rim around the point, and the
    /// leaning stem to the right
    static let expandedBodyReach = (minX: CGFloat(-0.87), maxX: CGFloat(0.75))
    /// The held top keeps at least this far from the screen's sides, moving away from an edge as it grows
    static let screenEdgeInset: CGFloat = 16
    static let dismissalDuration: TimeInterval = 0.28
    /// The backdrop around a resting top covers this multiple of its side, enough for the gentle resting lens
    static let restingBackdropScale: CGFloat = 1.5
    /// The backdrop around a held top covers its expanded canvas with this margin on each side, in points
    static let expandedBackdropMargin: CGFloat = 12
    static let backdropPixelsPerPoint: CGFloat = 2
    /// The top keeps still this long, as when scrolling stops, before its backdrop is captured again
    static let backdropSettleDelay: CFTimeInterval = 0.15
    /// A resting top refreshes its backdrop at this interval, to pick up content that changes behind it
    static let backdropRefreshInterval: CFTimeInterval = 2
    /// The resting canvas reaches this share of the side past each edge, so the leaning top is never clipped
    static let restingCanvasMargin: CGFloat = 0.1
    /// A press released this soon, within this distance of where it began, is a tap: the top also spins faster
    static let tapDuration: CFTimeInterval = 0.25
    static let tapMovement: CGFloat = 8
}

/// How the top wobbles as it spins: its axis leans and the lean goes around, faster the slower it spins, as a real
/// top's precession; the lean also nods a little. Taps spin it up, and it winds down to its own speed.
private enum SpinningTopPrecession {
    /// One turn of the lean every this many seconds at the regular spin
    static let period: Float = 2.1
    static let nodPeriod: Float = 1.35
    static let nodAmount: Float = 0.12
    /// Each tap adds the top's own speed and half of the boost it still has, so taps in a row spin it up faster
    /// and faster, up to this many times its own speed on top of it
    static let tapBoost: Float = 1
    static let tapBoostGrowth: Float = 0.5
    static let maximumBoost: Float = 12
    static let boostDecay: Float = 1.6
}

/// The Agent's 3D spinning top.
///
/// It spins on its own on its point, its leaning axis going around as a top's does. A touch grows it at once, up to
/// three times its resting size by default while held, and away from a screen edge it would cross; held, it can be
/// spun and tilted with a finger, turns clearer and refracts the content behind it more strongly. Taps spin it up,
/// faster with each tap in a row. One component serves every place the top appears; the speed multiplier sets its
/// own speed there.
///
/// While held, the top is drawn in the window above everything else. It shrinks away as soon as this view leaves
/// the window, is hidden, made transparent or inactive, or `dismiss()` is called, ending the touch.
public final class AgentSpinningTopView: UIView {
    /// One full turn every 1.2 s at the regular speed
    static let regularRotationSpeed: Float = 2 * .pi / 1.2

    private let metalView: SpinningTopMetalView?
    private let expandedScale: CGFloat
    private let centersExpandedTop: Bool
    private let fallbackView = UIImageView()
    /// While held, the Metal canvas lives in the window so its expanded size is never clipped or covered.
    /// The gesture stays on this view, so moving the canvas never interrupts the touch.
    private var isLifted = false
    /// The lifted canvas is shrinking away; it returns to this view when the animation ends
    private var isDismissing = false
    /// The captured backdrop's rectangle in this view's coordinates, so it moves along with scrolled content
    private var backdropRect = CGRect.zero
    private var backdropCenter: CGPoint?
    private var observedCenter: CGPoint?
    private var lastMovementTime: CFTimeInterval = 0
    private var lastCaptureTime: CFTimeInterval = 0
    private var isCaptureScheduled = false

    private lazy var pressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = .greatestFiniteMagnitude
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    public var isActive = true {
        didSet { updatePlayback() }
    }

    /// An opaque content view to sample when surrounding system effects cannot be rendered into a bitmap.
    public weak var backdropSourceView: UIView? {
        didSet {
            metalView?.setBackdrop(nil)
            backdropCenter = nil
            scheduleBackdropCapture()
        }
    }

    public init(speedMultiplier: Float = 1, expandedScale: CGFloat = 3, centersExpandedTop: Bool = false) {
        self.expandedScale = expandedScale
        self.centersExpandedTop = centersExpandedTop
        metalView = SpinningTopMetalView(
            rotationSpeed: Self.regularRotationSpeed * speedMultiplier,
            expandedScale: expandedScale,
            centersExpandedTop: centersExpandedTop
        )
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = lang("Agent")
        accessibilityTraits = .image
        if let metalView {
            metalView.isUserInteractionEnabled = false
            addSubview(metalView)
            addGestureRecognizer(pressGesture)
            metalView.onExpansionChanged = { [weak self] isExpanded in
                if !isExpanded { self?.settle() }
            }
            metalView.onFrame = { [weak self] in self?.handleFrame() }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reduceTransparencyChanged),
                name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                object: nil
            )
        } else {
            fallbackView.contentMode = .scaleAspectFit
            addSubview(fallbackView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let metalView {
            // A top squeezed for a moment by its row being measured keeps its size rather than draw tiny for a frame
            guard min(bounds.width, bounds.height) >= 4 || max(bounds.width, bounds.height) == 0 else { return }
            if !isLifted {
                metalView.setRestingFrame(bounds)
            } else if !isDismissing, let window {
                metalView.setRestingFrame(convert(bounds, to: window))
            }
        } else {
            fallbackView.frame = bounds
            if bounds.width > 0, fallbackView.image?.size.width != bounds.width {
                fallbackView.image = AgentSpinningTopIcon.makeImage(size: bounds.width)
            }
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        observedCenter = nil
        if window == nil {
            dismissLiftedCanvas()
        } else {
            scheduleBackdropCapture()
        }
        updatePlayback()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        // The content behind changes its colours too; until it is captured again the glass shows it directly
        metalView?.setBackdrop(nil)
        backdropCenter = nil
        scheduleBackdropCapture()
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let side = max(44, min(bounds.width, bounds.height))
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side).contains(point)
    }

    /// Ends any touch on the top; a top held over the screen shrinks away and returns here
    public func dismiss() {
        if isLifted {
            dismissLiftedCanvas()
        } else {
            cancelPress()
        }
    }

    private func updatePlayback() {
        let isActiveInWindow = isActive && window != nil
        if isLifted && !isActiveInWindow {
            dismissLiftedCanvas()
        }
        pressGesture.isEnabled = isActiveInWindow && !isDismissing
        // A shrinking canvas keeps drawing until it returns; `finishDismissal()` configures it then
        guard !isDismissing else { return }
        metalView?.configure(isActive: isActiveInWindow)
    }

    /// Whether the top can be seen where it rests: in a window, active, and with no hidden or transparent ancestor
    private var isPresentable: Bool {
        guard isActive, let window else { return false }
        var view: UIView = self
        while let superview = view.superview {
            if view.isHidden || view.alpha < 0.01 { return false }
            view = superview
        }
        return view === window && !window.isHidden
    }

    /// Runs at the start of every frame the canvas draws
    private func handleFrame() {
        guard let metalView, !isDismissing else { return }
        let isVisible = self.isPresentable
        if isLifted {
            guard let window, metalView.window === window, isVisible else {
                dismissLiftedCanvas()
                return
            }
            metalView.isIdle = false
            // The lifted canvas follows this view, for example while the list behind it scrolls
            metalView.setRestingFrame(convert(bounds, to: window))
        } else {
            metalView.isIdle = !isVisible
            if isVisible { trackBackdrop() }
        }
        if !backdropRect.isEmpty {
            metalView.backdropRect = metalView.convert(backdropRect, from: self)
        }
    }

    /// Captures the backdrop again once the resting top has kept still for a moment, and now and then while it rests
    private func trackBackdrop() {
        guard let window, !isCaptureScheduled, !UIAccessibility.isReduceTransparencyEnabled else { return }
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        let now = CACurrentMediaTime()
        if center != observedCenter {
            observedCenter = center
            lastMovementTime = now
            return
        }
        guard now - lastMovementTime >= SpinningTopMetrics.backdropSettleDelay else { return }
        let hasMoved = backdropCenter.map { abs($0.x - center.x) + abs($0.y - center.y) > 0.5 } ?? true
        if hasMoved || now - lastCaptureTime >= SpinningTopMetrics.backdropRefreshInterval {
            scheduleBackdropCapture()
        }
    }

    private func scheduleBackdropCapture() {
        guard metalView != nil, !isCaptureScheduled else { return }
        isCaptureScheduled = true
        // Outside the current layout pass and frame, so the capture sees the settled hierarchy
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCaptureScheduled = false
            if !self.isLifted { self.captureBackdrop(around: self.restingBackdropRect) }
        }
    }

    /// The backdrop of the resting top, around it, in this view's coordinates
    private var restingBackdropRect: CGRect {
        let side = max(bounds.width, bounds.height) * SpinningTopMetrics.restingBackdropScale
        return CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    /// Captures the content behind `rect`, in this view's coordinates
    private func captureBackdrop(around rect: CGRect) {
        guard let metalView, let device = metalView.device, let window, !rect.isEmpty, isPresentable,
              !UIAccessibility.isReduceTransparencyEnabled else { return }
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        let windowRect = convert(rect, to: window)
        let sourceView = backdropSourceView ?? window
        guard sourceView === window || sourceView.window === window else { return }
        let scale = min(SpinningTopMetrics.backdropPixelsPerPoint, window.screen.scale)
        lastCaptureTime = CACurrentMediaTime()
        guard let texture = SpinningTopBackdrop.capture(
            sourceView.convert(windowRect, from: window),
            in: sourceView,
            excluding: metalView.layer,
            scale: scale,
            device: device
        ) else { return }
        backdropRect = convert(windowRect, from: window)
        backdropCenter = center
        metalView.backdropRect = metalView.convert(backdropRect, from: self)
        metalView.setBackdrop(texture)
    }

    private func lift() {
        guard let metalView, let window, !isLifted, !isDismissing, isPresentable else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        metalView.expansionShift = getExpansionShift(in: window)
        let canvas = metalView.getExpandedCanvasRect(around: CGPoint(x: bounds.midX, y: bounds.midY))
        let margin = SpinningTopMetrics.expandedBackdropMargin
        captureBackdrop(around: canvas.insetBy(dx: -margin, dy: -margin))
        isLifted = true
        window.addSubview(metalView)
        metalView.setRestingFrame(convert(bounds, to: window))
        metalView.backdropRect = metalView.convert(backdropRect, from: self)
    }

    /// How far the growing top moves away from a side of the screen it would otherwise cross: a top near the edge
    /// grows toward the middle, keeping `screenEdgeInset` from the side, or as far as it is from it already
    private func getExpansionShift(in window: UIWindow) -> CGPoint {
        let resting = convert(bounds, to: window)
        let side = max(1, min(resting.width, resting.height))
        let unit = side / 2 / CGFloat(SpinningTopGeometry.boxHalfExtent) * expandedScale
        let reach = SpinningTopMetrics.expandedBodyReach
        let centeredOffset = centersExpandedTop ? -CGFloat(SpinningTopGeometry.restingOffset.x) * unit : 0
        let left = resting.midX + reach.minX * unit + centeredOffset
        let right = resting.midX + reach.maxX * unit + centeredOffset
        let bounds = window.bounds
        let leftInset = max(0, min(SpinningTopMetrics.screenEdgeInset, resting.minX - bounds.minX))
        let rightInset = max(0, min(SpinningTopMetrics.screenEdgeInset, bounds.maxX - resting.maxX))
        var shift: CGFloat = 0
        if left < bounds.minX + leftInset {
            shift = bounds.minX + leftInset - left
        } else if right > bounds.maxX - rightInset {
            shift = bounds.maxX - rightInset - right
        }
        return CGPoint(x: shift, y: 0)
    }

    private func settle() {
        guard let metalView, isLifted, !isDismissing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isLifted = false
        addSubview(metalView)
        metalView.setRestingFrame(bounds)
        metalView.backdropRect = metalView.convert(backdropRect, from: self)
    }

    /// Shrinks and fades the lifted canvas, then returns it to this view, even if this view is gone by then
    private func dismissLiftedCanvas() {
        guard let metalView, isLifted, !isDismissing else { return }
        isDismissing = true
        cancelPress()
        metalView.beginDismissal()
        let canvas = metalView
        let scale: CGFloat = UIAccessibility.isReduceMotionEnabled ? 1 : 0.01
        UIView.animate(
            withDuration: SpinningTopMetrics.dismissalDuration,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            canvas.transform = CGAffineTransform(scaleX: scale, y: scale)
            canvas.alpha = 0
        } completion: { [weak self] _ in
            canvas.removeFromSuperview()
            canvas.transform = .identity
            canvas.alpha = 1
            canvas.endDismissal()
            self?.finishDismissal()
        }
    }

    private func finishDismissal() {
        isDismissing = false
        isLifted = false
        guard let metalView else { return }
        addSubview(metalView)
        metalView.setRestingFrame(bounds)
        metalView.backdropRect = metalView.convert(backdropRect, from: self)
        updatePlayback()
    }

    /// Cancels a touch in progress; the gesture is enabled again by `updatePlayback()`
    private func cancelPress() {
        guard pressGesture.state == .began || pressGesture.state == .changed else { return }
        pressGesture.isEnabled = false
        pressGesture.isEnabled = isActive && window != nil && !isDismissing
    }

    @objc private func reduceTransparencyChanged() {
        if UIAccessibility.isReduceTransparencyEnabled {
            metalView?.setBackdrop(nil)
            backdropRect = .zero
            backdropCenter = nil
        } else {
            scheduleBackdropCapture()
        }
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard let metalView, !isDismissing else { return }
        if gesture.state == .began {
            lift()
            guard isLifted else { return }
        }
        metalView.handlePress(state: gesture.state, location: gesture.location(in: self))
    }
}

/// The content around the top, drawn from its background's layer tree into a texture
@MainActor private enum SpinningTopBackdrop {
    /// Draws `rect` of the source view, in its coordinates, without the excluded layer. Rendering the layer tree directly
    /// needs no screen update, so hiding the excluded layer for the capture never reaches the display.
    static func capture(
        _ rect: CGRect,
        in sourceView: UIView,
        excluding excludedLayer: CALayer,
        scale: CGFloat,
        device: MTLDevice
    ) -> MTLTexture? {
        let width = Int(ceil(rect.width * scale))
        let height = Int(ceil(rect.height * scale))
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ),
              let bytes = context.data else { return nil }
        // UIKit's top-left origin: the first row in memory is the top of `rect`, as the shader samples it
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        let isExcludedLayerHidden = excludedLayer.isHidden
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        excludedLayer.isHidden = true
        sourceView.layer.render(in: context)
        excludedLayer.isHidden = isExcludedLayerHidden
        CATransaction.commit()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Agent spinning top backdrop"
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: width * 4
        )
        return texture
    }
}

/// MetalKit canvas of the top: motion, press-to-grow and drawing
private final class SpinningTopMetalView: MTKView, MTKViewDelegate {
    private let renderer: SpinningTopRenderer
    private let queue: MTLCommandQueue
    private let renderTargets = DiamondRenderTargetCache()
    private let rotationSpeed: Float
    private let expandedScale: CGFloat
    private let centersExpandedTop: Bool
    private var motion = DiamondMotion()
    private var lastTime: CFTimeInterval?
    private var elapsed: Float = 0
    /// Where the lean points, turning as the top precesses; 0 leans to the right, as the mark does
    private var precessionPhase: Float = 0
    /// The spin a tap adds, in multiples of the top's own speed
    private var boostAmount: Float = 0
    private var isActive = false
    private var restingFrame = CGRect.zero
    /// The canvas's centre relative to the resting top's, in points, y down
    private var canvasOffset = CGPoint.zero
    private var grip: CGFloat = 0
    private var isHolding = false
    private var isCanvasExpanded = false
    /// While the lifted canvas shrinks away its size, position and grip stay as they are
    private var isFrozen = false
    private var expansion: Expansion?
    private var dragPosition: CGPoint?
    private var dragSamples: [(x: CGFloat, time: CFTimeInterval)] = []
    /// Where a press began while it can still turn out to be a tap
    private var tapOrigin: CGPoint?
    private var pressStartedAt: CFTimeInterval = 0
    private var backdrop: MTLTexture?
    private var landingFeedback: DispatchWorkItem?
    private let inFlight = DispatchSemaphore(value: 2)
    /// Inside `draw(in:)`, which presents the canvas's new size itself
    private var isDrawing = false
    /// The next frame presents with the Core Animation transaction that resizes the canvas, so the layer never shows
    /// the previous frame stretched to its new size, as one frame of a top grown threefold at once
    private var shouldPresentWithResize = false
    /// The backdrop's rectangle in this view's coordinates
    var backdropRect = CGRect.zero
    /// Set while the resting top cannot be seen: frames only run `onFrame`, at a low rate, until it can be again
    var isIdle = false {
        didSet {
            guard isIdle != oldValue else { return }
            lastTime = nil
            preferredFramesPerSecond = isIdle ? 4 : 60
        }
    }
    var onExpansionChanged: ((Bool) -> Void)?
    var onFrame: (() -> Void)?

    private struct Expansion {
        let start: CFTimeInterval
        let from: CGFloat
        let isHolding: Bool
    }

    init?(rotationSpeed: Float, expandedScale: CGFloat, centersExpandedTop: Bool) {
        guard let renderer = SpinningTopResources.renderer, let queue = SpinningTopResources.queue else { return nil }
        self.renderer = renderer
        self.queue = queue
        self.rotationSpeed = rotationSpeed
        self.expandedScale = expandedScale
        self.centersExpandedTop = centersExpandedTop
        super.init(frame: .zero, device: renderer.device)
        motion.swayScale = 0.45
        motion.releaseTilt = 2.2
        colorPixelFormat = .bgra8Unorm
        // The backdrop is captured in sRGB; matching the layer keeps it identical to the content around the top
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // MSAA and depth targets are owned by the cache, outside MetalKit's asynchronously resized buffers
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
        isAccessibilityElement = false
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlaybackChange), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(isActive: Bool) {
        guard self.isActive != isActive else { return }
        self.isActive = isActive
        if !isActive { suspend() }
        handlePlaybackChange()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        handlePlaybackChange()
        // A canvas resized while out of the window, as one returning from the window's overlay, draws its new size
        // before it shows
        if window != nil, shouldPresentWithResize, !isDrawing { draw() }
    }

    @objc private func handlePlaybackChange() {
        lastTime = nil
        let isVisible = isActive && window != nil && UIApplication.shared.applicationState == .active
        isPaused = !isVisible
        if window != nil && isPaused { draw() }
    }

    @objc func suspend() {
        landingFeedback?.cancel()
        landingFeedback = nil
        motion.end(at: CACurrentMediaTime(), cancelled: true)
        motion.stopSpin()
        dragPosition = nil
        dragSamples.removeAll(keepingCapacity: true)
        isHolding = false
        expansion = nil
        if !isFrozen { grip = 0 }
        lastTime = nil
        renderTargets.clear()
        updateCanvas()
        isPaused = true
    }

    func setBackdrop(_ texture: MTLTexture?) {
        backdrop = texture
        if isPaused && window != nil { draw() }
    }

    func setRestingFrame(_ frame: CGRect) {
        guard restingFrame != frame else { return }
        restingFrame = frame
        updateCanvas()
        if isPaused && window != nil { draw() }
    }

    /// Stops the interaction and keeps the canvas as it is while it shrinks away
    func beginDismissal() {
        landingFeedback?.cancel()
        landingFeedback = nil
        if motion.isDragging { motion.end(at: CACurrentMediaTime(), cancelled: true) }
        dragPosition = nil
        dragSamples.removeAll(keepingCapacity: true)
        isHolding = false
        expansion = nil
        isFrozen = true
    }

    /// Returns the canvas to the resting size after it has shrunk away
    func endDismissal() {
        isFrozen = false
        isHolding = false
        expansion = nil
        grip = 0
        renderTargets.clear()
        updateCanvas()
    }

    private var restingSide: CGFloat {
        max(1, min(restingFrame.width, restingFrame.height))
    }

    /// Where the held top moves to keep off the screen's sides, in points; it gets there as it grows
    var expansionShift = CGPoint.zero

    /// Points per model unit of the expanded top
    private var expandedUnit: CGFloat {
        restingSide / 2 / CGFloat(SpinningTopGeometry.boxHalfExtent) * expandedScale
    }

    /// The expanded canvas: it covers wherever the expanded top can reach, so tilting it never clips it
    private var expandedCanvasSize: CGSize {
        let reach = SpinningTopMetrics.expandedReach
        let margin = 2 * SpinningTopMetrics.expandedReachMargin
        let minimum = SpinningTopMetrics.minimumExpandedCanvasSide
        return CGSize(
            width: max(minimum, ceil((reach.maxX - reach.minX + margin) * expandedUnit)),
            height: max(minimum, ceil((reach.maxY - reach.minY + margin) * expandedUnit))
        )
    }

    /// The expanded canvas's centre relative to the resting top's, in points, y down
    private var expandedCanvasOffset: CGPoint {
        let reach = SpinningTopMetrics.expandedReach
        let centeredOffset = centersExpandedTop ? -CGFloat(SpinningTopGeometry.restingOffset.x) * expandedUnit : 0
        return CGPoint(
            x: (reach.minX + reach.maxX) / 2 * expandedUnit + expansionShift.x + centeredOffset,
            y: -(reach.minY + reach.maxY) / 2 * expandedUnit + expansionShift.y
        )
    }

    /// The expanded canvas for a resting top centred at `center`, in the same coordinates
    func getExpandedCanvasRect(around center: CGPoint) -> CGRect {
        let size = expandedCanvasSize
        let offset = expandedCanvasOffset
        return CGRect(
            x: center.x + offset.x - size.width / 2,
            y: center.y + offset.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func updateExpansion(at now: CFTimeInterval) {
        guard let expansion else { return }
        let elapsed = max(0, now - expansion.start)
        if expansion.isHolding {
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

    private func setHolding(_ isHolding: Bool, at now: CFTimeInterval) {
        guard self.isHolding != isHolding else { return }
        updateExpansion(at: now)
        self.isHolding = isHolding
        if UIAccessibility.isReduceMotionEnabled {
            expansion = nil
            grip = isHolding ? 1 : 0
        } else {
            expansion = Expansion(start: now, from: grip, isHolding: isHolding)
        }
        updateCanvas()
    }

    /// Sizes the canvas through `bounds` and `center`, which stay valid while the dismissal scales it
    private func updateCanvas() {
        guard !isFrozen else { return }
        let isExpanded = isHolding || expansion != nil
        let margin = restingSide * SpinningTopMetrics.restingCanvasMargin * 2
        let size = isExpanded
            ? expandedCanvasSize
            : CGSize(width: restingFrame.width + margin, height: restingFrame.height + margin)
        let offset = isExpanded ? expandedCanvasOffset : .zero
        canvasOffset = offset
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let pixels = CGSize(width: max(1, ceil(size.width * scale)), height: max(1, ceil(size.height * scale)))
        let needsNewFrame = bounds.size != size || contentScaleFactor != scale || drawableSize != pixels
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if needsNewFrame {
            shouldPresentWithResize = true
            (layer as? CAMetalLayer)?.presentsWithTransaction = true
        }
        bounds = CGRect(origin: .zero, size: size)
        center = CGPoint(x: restingFrame.midX + offset.x, y: restingFrame.midY + offset.y)
        contentScaleFactor = scale
        // MTKView can reevaluate its drawable while bounds or display scale changes.
        if drawableSize != pixels { drawableSize = pixels }
        preferredFramesPerSecond = isIdle ? 4 : isExpanded ? (window?.screen.maximumFramesPerSecond ?? 120) : 60
        if needsNewFrame, window != nil, !isDrawing { draw() }
        // Commit the new geometry together with its new drawable, never with the previously sized image.
        CATransaction.commit()
        if isCanvasExpanded != isExpanded {
            isCanvasExpanded = isExpanded
            onExpansionChanged?(isExpanded)
        }
    }

    /// Spins the top up, faster with every tap in a row; it winds down again to its own speed
    private func boost() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let added = SpinningTopPrecession.tapBoost + SpinningTopPrecession.tapBoostGrowth * boostAmount
        boostAmount = min(SpinningTopPrecession.maximumBoost, boostAmount + added)
    }

    private func updateMotion(at now: CFTimeInterval) {
        let timeStep = Float(lastTime.map { min(max(0, now - $0), 0.05) } ?? 0)
        lastTime = now
        let isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        if !isReduceMotionEnabled { elapsed += timeStep }
        motion.step(dt: timeStep, speed: rotationSpeed, reduceMotion: isReduceMotionEnabled, mode: .continuous, time: elapsed)
        if isReduceMotionEnabled {
            boostAmount = 0
            precessionPhase = 0
        } else {
            motion.externalYaw += rotationSpeed * boostAmount * timeStep
            boostAmount *= exp(-timeStep / SpinningTopPrecession.boostDecay)
            if boostAmount < 0.001 { boostAmount = 0 }
            // The faster the top spins, the slower its lean goes around
            let rate = 2 * Float.pi / SpinningTopPrecession.period
                * rotationSpeed / AgentSpinningTopView.regularRotationSpeed
            precessionPhase = (precessionPhase + rate * timeStep / (1 + boostAmount))
                .truncatingRemainder(dividingBy: 2 * .pi)
        }
        updateExpansion(at: now)
        updateCanvas()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        isDrawing = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
            isDrawing = false
        }
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
        onFrame?()
        guard !isIdle else { return }
        updateMotion(at: CACurrentMediaTime())
        // A frame for a resized canvas waits briefly for the GPU rather than leave the layer stretched
        let wait: DispatchTime = shouldPresentWithResize ? .now() + 0.008 : .now()
        guard window != nil, bounds.width > 0, bounds.height > 0,
              inFlight.wait(timeout: wait) == .success else { return }
        guard let drawable = currentDrawable,
              let pass = renderTargets.renderPass(resolving: drawable.texture, sampleCount: renderer.sampleCount),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let texture = drawable.texture
        let pixelsPerPoint = Float(texture.width) / Float(bounds.width)
        let strength = Float(min(1, max(0, grip)))
        let grow = Float(1 + (expandedScale - 1) * grip)
        let pixelsPerUnit = Float(restingSide) / 2 * pixelsPerPoint / SpinningTopGeometry.boxHalfExtent * grow
        // The point rests where the mark has it, which centres the top in its box. The box sits on the resting top,
        // moving away from a screen edge as the top grows, wherever the canvas around it is.
        let offset = SpinningTopGeometry.restingOffset * pixelsPerUnit
        let centeredOffset = centersExpandedTop ? -offset.x * strength : 0
        let shiftShare = min(1, max(0, grip))
        let boxOffset = CGPoint(
            x: expansionShift.x * shiftShare - canvasOffset.x,
            y: expansionShift.y * shiftShare - canvasOffset.y
        )
        let centre = SIMD2<Float>(Float(texture.width) / 2, Float(texture.height) / 2) + offset
            + SIMD2(Float(boxOffset.x), -Float(boxOffset.y)) * pixelsPerPoint
            + SIMD2(centeredOffset, 0)
        let hasBackdrop = backdrop != nil && backdropRect.width > 0 && backdropRect.height > 0
        let backdropPixels = SIMD4<Float>(
            Float(backdropRect.minX),
            Float(backdropRect.minY),
            Float(backdropRect.width),
            Float(backdropRect.height)
        ) * pixelsPerPoint
        let pitch = motion.pitch - DiamondMotion.referencePitch + SpinningTopGeometry.viewPitch
        // A faster spin stands the top up; held, it leans half as much
        let nod = 1 + SpinningTopPrecession.nodAmount * sin(2 * .pi * elapsed / SpinningTopPrecession.nodPeriod)
        let lean = SpinningTopGeometry.lean * nod / (1 + boostAmount).squareRoot() * (1 - strength * 0.5)
        let uniforms = SpinningTopRenderer.Uniforms(
            rotation: SpinningTopRenderer.transform(
                yaw: motion.renderedYaw,
                pitch: pitch,
                lean: UIAccessibility.isReduceMotionEnabled ? SpinningTopGeometry.lean : lean,
                leanDirection: precessionPhase
            ),
            placement: SIMD4(centre.x, centre.y, pixelsPerUnit, Float(texture.height)),
            parameters: SIMD4(
                Float(texture.width),
                strength,
                traitCollection.userInterfaceStyle == .dark ? 1 : 0,
                hasBackdrop ? 1 : 0
            ),
            backdrop: backdropPixels,
            material: SIMD4(
                0.25 * strength,
                UIAccessibility.isReduceTransparencyEnabled ? 0.92 : 0,
                -SpinningTopGeometry.restingOffset.x,
                -SpinningTopGeometry.restingOffset.y
            )
        )
        renderer.encode(encoder: encoder, uniforms: uniforms, backdrop: hasBackdrop ? backdrop : nil)
        encoder.endEncoding()
        command.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        if shouldPresentWithResize {
            // Shown in the same transaction as the canvas's new size
            shouldPresentWithResize = false
            command.commit()
            command.waitUntilScheduled()
            drawable.present()
            (layer as? CAMetalLayer)?.presentsWithTransaction = false
        } else {
            command.present(drawable)
            command.commit()
        }
    }

    func handlePress(state: UIGestureRecognizer.State, location point: CGPoint) {
        guard !isFrozen else { return }
        let now = CACurrentMediaTime()
        updateMotion(at: now)
        switch state {
        case .began:
            landingFeedback?.cancel()
            SpinningTopResources.haptic.prepare()
            tapOrigin = point
            pressStartedAt = now
            dragPosition = point
            dragSamples = [(point.x, now)]
            motion.begin(at: now)
            setHolding(true, at: now)
        case .changed, .ended:
            guard let previous = dragPosition, motion.isDragging else { return }
            if let origin = tapOrigin, hypot(point.x - origin.x, point.y - origin.y) > SpinningTopMetrics.tapMovement {
                tapOrigin = nil
            }
            let releasePower = grip
            let translation = CGPoint(x: point.x - previous.x, y: point.y - previous.y)
            dragSamples.append((point.x, now))
            while dragSamples.count > 2 && dragSamples[0].time < now - 0.08 { dragSamples.removeFirst() }
            let sample = dragSamples[0]
            let interval = CGFloat(max(now - sample.time, 1 / 240.0))
            let velocity = (point.x - sample.x) / interval
            dragPosition = state == .ended ? nil : point
            if translation != .zero {
                motion.drag(dx: Float(translation.x), dy: Float(translation.y), scale: 220, at: now)
            }
            if state == .ended {
                dragSamples.removeAll(keepingCapacity: true)
                motion.step(dt: 0, speed: rotationSpeed, reduceMotion: UIAccessibility.isReduceMotionEnabled, time: elapsed)
                motion.end(at: now)
                if tapOrigin != nil && now - pressStartedAt <= SpinningTopMetrics.tapDuration {
                    boost()
                } else if abs(velocity) > 600 && !UIAccessibility.isReduceMotionEnabled {
                    motion.fling(direction: velocity < 0 ? -1 : 1, impulse: 6 * 6.5)
                }
                tapOrigin = nil
                setHolding(false, at: now)
                scheduleLanding(power: releasePower)
            }
        case .cancelled, .failed:
            landingFeedback?.cancel()
            tapOrigin = nil
            dragPosition = nil
            dragSamples.removeAll(keepingCapacity: true)
            motion.end(at: now, cancelled: true)
            setHolding(false, at: now)
        default:
            break
        }
        updateCanvas()
        if isPaused { draw() }
    }

    private func scheduleLanding(power: CGFloat) {
        guard power > 0.2, !isHolding else { return }
        let feedback = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil, !self.isHolding, !self.isFrozen else { return }
            SpinningTopResources.haptic.impactOccurred(intensity: 0.35 + 0.4 * min(1, power))
            SpinningTopResources.haptic.prepare()
        }
        landingFeedback = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: feedback)
    }
}
