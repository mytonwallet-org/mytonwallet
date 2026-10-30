//
//  LaunchSplash.swift
//  AirAsFramework
//
//  Animated continuation of the launch screen: the app icon ribbon, cut from the icon art
//  itself, gets "trim-pathed" away along its zigzag while the blue background fades out
//  over the already loaded app.
//
//  Lives in its own window above the app, so it never touches the startup flow:
//  the app loads underneath as usual, and the splash only waits for the first
//  root screen before playing.
//

import UIKit
import WalletContext

/// Tweakable motion values, seconds. One gesture: the ribbon is trimmed away on an iOS spring
/// while it comes slightly towards the camera and the blue fades out over the app.
enum LaunchSplashTiming {
    /// iOS cross-fades its static launch snapshot away over the app's first frames; starting
    /// earlier would leave a ghost of the full logo over the trim. Counted from the splash showing.
    static let launchSnapshotFadeOut: TimeInterval = 0.25

    /// Spring of the trim and of the scale, same meaning as SwiftUI `.spring(response:dampingFraction:)`:
    /// response ≈ how long it takes, dampingFraction 1 = no overshoot.
    static let springResponse: Double = 0.75
    static let springDampingFraction: Double = 1
    /// Ribbon scale at the end of the trim (it comes towards the camera while leaving).
    static let endScale: CGFloat = 1.06
    /// Share of the trim time each piece gets, relative to its length (left strip, fold, middle
    /// strip, fold, right strip). < 1 = that piece goes by faster.
    static let pieceTimeWeights: [CGFloat] = [1, 1, 1, 1, 0.55]
    /// The spring's slow tail is cut: the trim ends once the spring reaches this share.
    static let springEndThreshold: Double = 0.985
    /// How finely the spring is sampled into keyframes.
    static let keyframeCount = 60

    /// Blue background opacity 1 → 0; ease-out curve control points. Starts `backgroundFadeDelay`
    /// after the ribbon, but never before the app has actually drawn its first screen.
    static let backgroundFadeDelay: TimeInterval = 0.35
    static let backgroundFadeDuration: TimeInterval = 0.5
    static let backgroundFadeCurve: (Float, Float, Float, Float) = (0.2, 0, 0, 1)

    /// Plays anyway if the app has not shown its first screen by then.
    static let maxWaitForApp: TimeInterval = 8
    /// Plain fade used with Reduce Motion.
    static let reducedMotionFadeDuration: TimeInterval = 0.25
}

@MainActor
enum LaunchSplash {
    private static var controller: LaunchSplashController?
    private static var didPlay = false

    static func show(over window: UIWindow) {
        guard controller == nil, !didPlay, let windowScene = window.windowScene,
              let controller = LaunchSplashController(windowScene: windowScene) else { return }
        self.controller = controller
        controller.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchSplashTiming.maxWaitForApp) {
            play()
        }
    }

    /// Call once the first root screen is attached. Safe to call repeatedly.
    static func play() {
        guard !didPlay, let controller else { return }
        didPlay = true
        // Synchronously: right after the first screen is attached the main thread stays busy
        // with startup for a while, and anything queued on it would start late.
        StartupTrace.mark("launchSplash.play")
        controller.play {
            LaunchSplash.controller = nil
        }
    }
}

@MainActor
private final class LaunchSplashController {
    private typealias Geometry = LaunchSplashGeometry

    private let window: UIWindow
    private let images: [CGImage]
    private let tipImage: CGImage
    private let backgroundView = UIView()
    private let ribbonView = UIView()
    private var pieceViews: [RibbonPieceView] = []
    private var shownAt: CFTimeInterval = 0

    /// Fails when the piece images are missing (other app flavors), then there is no splash.
    init?(windowScene: UIWindowScene) {
        let images = Geometry.pieces.compactMap { UIImage(named: $0.imageName)?.cgImage }
        guard images.count == Geometry.pieces.count,
              let tipImage = UIImage(named: Geometry.tipImageName)?.cgImage else { return nil }
        self.images = images
        self.tipImage = tipImage
        window = UIWindow(windowScene: windowScene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.isUserInteractionEnabled = false
        window.rootViewController = LaunchSplashViewController()
    }

    func show() {
        guard let rootView = window.rootViewController?.view else { return }
        let bounds = window.bounds
        rootView.frame = bounds

        // Same layout as the launch storyboard: logo in the top square, outer strips running
        // past the screen edges, background gradient image stretched over the screen.
        let layout = Geometry.Layout(screenSize: bounds.size)
        backgroundView.frame = bounds
        backgroundView.layer.contents = UIImage(named: Geometry.backgroundImageName)?.cgImage
        backgroundView.layer.contentsGravity = .resize
        rootView.addSubview(backgroundView)

        ribbonView.frame = bounds
        // Scale towards the camera around the icon center.
        ribbonView.layer.anchorPoint = CGPoint(x: 0.5, y: layout.center.y / bounds.height)
        ribbonView.layer.position = layout.center
        rootView.addSubview(ribbonView)
        var folds = Geometry.foldOutlines.makeIterator()
        pieceViews = Geometry.pieces.enumerated().map { index, piece in
            let rect = Geometry.screenRect(of: piece, layout: layout)
            let line = Geometry.trimLine(of: piece, screenRect: rect, layout: layout)
            let shape: RibbonPieceView.TrimShape = piece.direction.dx == 0 ? .stripTip(tipImage) : .foldOutline(folds.next()!)
            return RibbonPieceView(frame: bounds, piece: piece, image: images[index], artRect: rect,
                                   trimLine: line, trimShape: shape, layout: layout)
        }
        for index in Geometry.drawOrder {
            ribbonView.addSubview(pieceViews[index])
        }

        window.isHidden = false
        shownAt = CACurrentMediaTime()
        // Scene connection runs inside UIKit's own transaction, and startup right after it
        // keeps the main thread busy, so present the first frame from a job that runs first.
        Task { @MainActor in
            CATransaction.flush()
        }
    }

    func play(completion: @escaping () -> Void) {
        guard UIView.areAnimationsEnabled else {
            finish(completion)
            return
        }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: LaunchSplashTiming.reducedMotionFadeDuration, animations: {
                self.window.rootViewController?.view.alpha = 0
            }, completion: { _ in
                self.finish(completion)
            })
            return
        }

        let begin = max(CACurrentMediaTime(), shownAt + LaunchSplashTiming.launchSnapshotFadeOut)
        let spring = Spring(response: LaunchSplashTiming.springResponse, dampingFraction: LaunchSplashTiming.springDampingFraction)
        let duration = spring.time(reaching: LaunchSplashTiming.springEndThreshold)
        let samples = LaunchSplashTiming.keyframeCount
        let keyTimes = (0...samples).map { Double($0) / Double(samples) }
        let eased = keyTimes.map { min(CGFloat(spring.value(at: $0 * duration) / LaunchSplashTiming.springEndThreshold), 1) }

        // Trim runs as keyframes on the render server, so it stays smooth while the main
        // thread is still busy with startup. One spring progress over the whole ribbon is
        // spread across the pieces by their length.
        let lengths = pieceViews.enumerated().map { index, view in
            view.trimLength * LaunchSplashTiming.pieceTimeWeights[index]
        }
        let total = lengths.reduce(0, +)
        var offset: CGFloat = 0
        let offsets = lengths.map { length in
            defer { offset += length }
            return offset
        }

        // Done when both the ribbon and the background are.
        var pending = 2
        let done = {
            pending -= 1
            if pending == 0 { self.finish(completion) }
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock(done)

        for (index, pieceView) in pieceViews.enumerated() {
            let values = eased.map { min(max(($0 * total - offsets[index]) / lengths[index], 0), 1) }
            pieceView.animateTrim(values: values, keyTimes: keyTimes, beginTime: begin, duration: duration)
        }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = eased.map { 1 + (LaunchSplashTiming.endScale - 1) * $0 }
        scale.keyTimes = keyTimes.map { NSNumber(value: $0) }
        scale.calculationMode = .linear
        scale.beginTime = begin
        scale.duration = duration
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        ribbonView.layer.add(scale, forKey: "scale")

        CATransaction.commit()
        // Hand the animations to the render server now; startup keeps the main thread busy.
        CATransaction.flush()

        // The first screen is attached but drawn only once startup lets the main thread go;
        // a job queued now runs right then.
        DispatchQueue.main.async {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let curve = LaunchSplashTiming.backgroundFadeCurve
            fade.timingFunction = CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)
            fade.beginTime = max(CACurrentMediaTime(), begin + LaunchSplashTiming.backgroundFadeDelay)
            fade.duration = LaunchSplashTiming.backgroundFadeDuration
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock(done)
            self.backgroundView.layer.add(fade, forKey: "fade")
            CATransaction.commit()
        }
    }

    private func finish(_ completion: () -> Void) {
        window.isHidden = true
        window.rootViewController = nil
        completion()
    }
}

private final class LaunchSplashViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

/// One piece of the ribbon: the icon art (optionally stretched past the screen edge), fully
/// opaque like the icon, masked by a trim mask that slides along the piece.
/// The mask's leading edge is a real ribbon tip, so the moving end looks like the logo's ends:
/// strips use the middle strip's bottom tip, folds use their own outline.
private final class RibbonPieceView: UIView {
    enum TrimShape {
        case stripTip(CGImage)
        case foldOutline(CGPath)
    }

    private let trimMask: CALayer
    private let piece: LaunchSplashGeometry.Piece
    private let image: CGImage
    private let artRect: CGRect
    let trimLine: (start: CGPoint, end: CGPoint)
    let trimLength: CGFloat

    init(frame: CGRect, piece: LaunchSplashGeometry.Piece, image: CGImage, artRect: CGRect,
         trimLine: (start: CGPoint, end: CGPoint), trimShape: TrimShape, layout: LaunchSplashGeometry.Layout) {
        trimLength = hypot(trimLine.end.x - trimLine.start.x, trimLine.end.y - trimLine.start.y)
        self.piece = piece
        self.image = image
        self.artRect = artRect
        self.trimLine = trimLine
        let scale = layout.scale
        let center = layout.center
        switch trimShape {
        case .stripTip(let tip):
            // Tip at the bottom, its top row stretched up past the whole strip.
            let mask = CALayer()
            mask.contents = tip
            mask.contentsScale = LaunchSplashGeometry.pieceImagePixelsPerUnit / scale
            mask.contentsCenter = CGRect(x: 0, y: 0, width: 1, height: 1 / CGFloat(tip.height))
            let tipHeight = LaunchSplashGeometry.tipRect.height * scale
            mask.bounds = CGRect(x: 0, y: 0, width: artRect.width, height: tipHeight + trimLength + artRect.height)
            trimMask = mask
        case .foldOutline(let outline):
            var toScreen = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -256, y: -256)
            let mask = CAShapeLayer()
            mask.bounds = CGRect(origin: .zero, size: frame.size)
            mask.path = outline.copy(using: &toScreen)
            mask.fillColor = UIColor.black.cgColor
            trimMask = mask
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false

        let artView = UIView(frame: artRect)
        Self.configureArtLayer(artView.layer, image: image, piece: piece, scale: scale)
        addSubview(artView)


        trimMask.position = maskPosition(trimmed: 0)
        layer.mask = trimMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Where the mask sits when `fraction` of the piece is eaten.
    private func maskPosition(trimmed fraction: CGFloat) -> CGPoint {
        if trimMask is CAShapeLayer {
            // The outline slides along the fold; overlap with the art is what stays visible.
            let shift = fraction * trimLength * 1.02
            let d = piece.direction
            return CGPoint(x: bounds.midX + d.dx * shift, y: bounds.midY + d.dy * shift)
        }
        let front = trimLine.start.y + (trimLine.end.y - trimLine.start.y) * fraction
        return CGPoint(x: artRect.midX, y: front - trimMask.bounds.height / 2)
    }

    /// Fills forwards only, so a later phase never jumps the mask back before it begins.
    func animateTrim(values: [CGFloat], keyTimes: [Double], beginTime: CFTimeInterval, duration: TimeInterval,
                     timing: CAMediaTimingFunction? = nil, key: String = "trim") {
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = values.map { NSValue(cgPoint: maskPosition(trimmed: $0)) }
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.beginTime = beginTime
        animation.duration = duration
        animation.timingFunction = timing
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        trimMask.add(animation, forKey: key)
    }

    /// The piece image at its natural scale, with the edge row stretched for extended strips.
    private static func configureArtLayer(_ layer: CALayer, image: CGImage, piece: LaunchSplashGeometry.Piece, scale: CGFloat) {
        layer.contents = image
        layer.contentsScale = LaunchSplashGeometry.pieceImagePixelsPerUnit / scale
        let row = 1 / CGFloat(image.height)
        switch piece.extends {
        case .none:
            break
        case .down:
            layer.contentsCenter = CGRect(x: 0, y: 1 - row, width: 1, height: row)
        case .up:
            layer.contentsCenter = CGRect(x: 0, y: 0, width: 1, height: row)
        }
    }
}

/// Damped spring from 0 to 1, same parameters as SwiftUI `.spring(response:dampingFraction:)`.
private struct Spring {
    let response: Double
    let dampingFraction: Double

    func value(at t: Double) -> Double {
        let omega = 2 * .pi / response
        let zeta = dampingFraction
        if zeta >= 1 {
            return 1 - (1 + omega * t) * exp(-omega * t)
        }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }

    /// First time the spring reaches `share` of its target.
    func time(reaching share: Double) -> Double {
        var t = 0.0
        while value(at: t) < share, t < response * 4 { t += 0.002 }
        return t
    }

    /// Time until the spring stays within 0.1% of its target.
    var settlingDuration: Double {
        var t = response * 3
        while t > response, abs(1 - value(at: t - 0.01)) < 0.001 {
            t -= 0.01
        }
        return t
    }
}
