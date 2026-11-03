import SwiftUI
import UIKit
import WalletContext

public final class WSpeedingDiamondView: UIView {
    public var onMove: (() -> Void)?
    public var onPressChange: ((Bool) -> Void)?
    public var onHoverChange: ((Bool) -> Void)?

    private let animationSize: CGFloat
    private let stickerView = WAnimatedSticker()
    private var slowdownDisplayLink: CADisplayLink?
    private var slowdownStartedAt: CFTimeInterval = 0
    private var lastBurstAt: CFTimeInterval = 0
    private var didSetupAnimation = false
    private var didMoveDuringTouch = false
    private var touchStartLocation: CGPoint?

    public init(size: CGFloat = 130) {
        self.animationSize = size
        super.init(frame: .zero)
        setup()
    }

    public override init(frame: CGRect) {
        self.animationSize = max(max(frame.width, frame.height), 130)
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        slowdownDisplayLink?.invalidate()
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(startSlowdown),
            object: nil
        )
    }

    public func start() {
        guard !didSetupAnimation else {
            stickerView.play()
            return
        }
        didSetupAnimation = true
        stickerView.animationName = "diamond"
        stickerView.playbackSpeed = Self.minSpeed
        stickerView.setup(width: Int(animationSize), height: Int(animationSize), playbackMode: .loop, bundle: .main)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            onPressChange?(false)
            onHoverChange?(false)
            stopSlowdown()
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(startSlowdown),
                object: nil
            )
        } else {
            stickerView.play()
        }
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didMoveDuringTouch = false
        touchStartLocation = touches.first?.location(in: self)
        animatePressed(true)
        onPressChange?(true)
        handleMove()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let touchStartLocation, let location = touches.first?.location(in: self) {
            let distance = abs(location.x - touchStartLocation.x) + abs(location.y - touchStartLocation.y)
            if distance > Self.tapMovementTolerance {
                didMoveDuringTouch = true
            }
        }
        handleMove()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchStartLocation = nil
        onPressChange?(false)
        if didMoveDuringTouch {
            animatePressed(false)
        } else {
            animateTap()
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchStartLocation = nil
        onPressChange?(false)
        animatePressed(false)
    }

    private func setup() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))

        stickerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stickerView)
        NSLayoutConstraint.activate([
            stickerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stickerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stickerView.widthAnchor.constraint(equalToConstant: animationSize),
            stickerView.heightAnchor.constraint(equalToConstant: animationSize),
        ])
    }

    @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
        onHoverChange?(gesture.state == .began || gesture.state == .changed)
    }

    private func handleMove() {
        stopSlowdown()
        stickerView.playbackSpeed = Self.maxSpeed
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(startSlowdown),
            object: nil
        )
        perform(#selector(startSlowdown), with: nil, afterDelay: Self.slowdownDelay)

        let now = CACurrentMediaTime()
        if now - lastBurstAt >= Self.burstMinInterval {
            lastBurstAt = now
            onMove?()
        }
    }

    @objc private func startSlowdown() {
        stopSlowdown()
        slowdownStartedAt = CACurrentMediaTime()
        let displayLink = CADisplayLink(target: self, selector: #selector(updateSlowdown(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        slowdownDisplayLink = displayLink
    }

    @objc private func updateSlowdown(_ displayLink: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - slowdownStartedAt
        let progress = min(max(elapsed / Self.slowdownDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 2)
        stickerView.playbackSpeed = Self.minSpeed + (Self.maxSpeed - Self.minSpeed) * (1 - eased)
        if progress >= 1 {
            stickerView.playbackSpeed = Self.minSpeed
            stopSlowdown()
        }
    }

    private func stopSlowdown() {
        slowdownDisplayLink?.invalidate()
        slowdownDisplayLink = nil
    }

    private func animatePressed(_ pressed: Bool) {
        UIView.animate(withDuration: Self.scaleDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.transform = pressed ? CGAffineTransform(scaleX: Self.pressedScale, y: Self.pressedScale) : .identity
        }
    }

    private func animateTap() {
        UIView.animate(withDuration: Self.tapScaleUpDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.transform = CGAffineTransform(scaleX: Self.pressedScale, y: Self.pressedScale)
        } completion: { _ in
            UIView.animate(withDuration: Self.scaleDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.transform = .identity
            }
        }
    }

    private static let minSpeed = 1.0
    private static let maxSpeed = 5.0
    private static let slowdownDelay = 0.3
    private static let slowdownDuration = 1.5
    private static let burstMinInterval: CFTimeInterval = 0.008
    private static let pressedScale: CGFloat = 1.1
    private static let scaleDuration = 0.25
    private static let tapScaleUpDuration = 0.12
    private static let tapMovementTolerance: CGFloat = 6
}

public struct WUISpeedingDiamond: UIViewRepresentable {
    public var size: CGFloat
    public var onMove: () -> Void
    public var onPressChange: (Bool) -> Void
    public var onHoverChange: (Bool) -> Void

    public init(size: CGFloat = 130, onPressChange: @escaping (Bool) -> Void = { _ in },
                onHoverChange: @escaping (Bool) -> Void = { _ in }, onMove: @escaping () -> Void = {}) {
        self.size = size
        self.onMove = onMove
        self.onPressChange = onPressChange
        self.onHoverChange = onHoverChange
    }

    public func makeUIView(context: Context) -> WSpeedingDiamondView {
        let view = WSpeedingDiamondView(size: size)
        view.onMove = onMove
        view.onPressChange = onPressChange
        view.onHoverChange = onHoverChange
        view.start()
        return view
    }

    public func updateUIView(_ uiView: WSpeedingDiamondView, context: Context) {
        uiView.onMove = onMove
        uiView.onPressChange = onPressChange
        uiView.onHoverChange = onHoverChange
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: WSpeedingDiamondView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

public struct WUISpeedingDiamondWithParticles: View {
    public var diamondSize: CGFloat
    public var particleSize: CGSize
    public var isWelcome: Bool

    @State private var burstTrigger = 0
    @State private var isPressed = false
    @State private var isHovered = false

    public init(
        diamondSize: CGFloat = 130,
        particleSize: CGSize = CGSize(width: 350, height: 230),
        isWelcome: Bool = false
    ) {
        self.diamondSize = diamondSize
        self.particleSize = particleSize
        self.isWelcome = isWelcome
    }

    public var body: some View {
        ZStack {
            SparkleParticleBackground(canvasSize: particleSize, burstTrigger: $burstTrigger,
                                      isWelcome: isWelcome, welcomeColor: .tintColor,
                                      isHovered: isHovered, isPressed: isPressed)
                .frame(width: isWelcome ? 386 : particleSize.width, height: isWelcome ? 268 : particleSize.height)
                .offset(y: isWelcome ? -10 : 0)
                .allowsHitTesting(false)
            if isWelcome && TelegramDiamondView.isAvailable {
                TelegramDiamondView(size: diamondSize * 1.5, stoneWidth: diamondSize,
                    maxGrow: 1.15, hoverSpeed: 2, shouldRotateOnTap: true,
                    onPressChange: { isPressed = $0 }, onHoverChange: { isHovered = $0 })
                    .frame(width: diamondSize, height: diamondSize)
            } else {
                WUISpeedingDiamond(size: diamondSize, onPressChange: { isPressed = $0 }, onHoverChange: { isHovered = $0 }, onMove: {
                    if !isWelcome { burstTrigger += 1 }
                })
                .frame(width: diamondSize, height: diamondSize)
            }
        }
        .frame(width: diamondSize, height: diamondSize)
        .accessibilityHidden(true)
        .onDisappear {
            isPressed = false
            isHovered = false
        }
    }
}
