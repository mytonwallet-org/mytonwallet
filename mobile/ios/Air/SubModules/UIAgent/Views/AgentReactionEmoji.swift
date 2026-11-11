import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The animations of a reaction's emoji: Telegram's, as its reactions panel and messages play them, and the burst of
/// our own around a landing reaction
enum AgentReactionAnimation: String, CaseIterable {
    /// Plays once as the cloud shows the reaction
    case appear
    /// Plays once under the finger; its first frame is the reaction's still icon
    case select
    /// Plays once at the answer's corner as the reaction lands there, which rests on its last frame
    case center
    /// The burst around the answer's corner as a chosen reaction lands, on Telegram's 512 px canvas at 60 fps
    case burst
}

enum AgentReactionEmojiMetrics {
    /// The cloud's animations play in a box a little larger than its 36 pt icon, where the emoji is as wide as an icon
    /// drawn to that size
    static let cloudBoxSize: CGFloat = 38
    /// The corner's animation plays in twice its 22 pt icon, as Telegram's expanded reaction does
    static let badgeBoxSize: CGFloat = 44
    /// The burst around a chosen reaction: three times the corner's box
    static let burstSize: CGFloat = 132
    /// The bursts render at Telegram's 1.33 pixels per point, which their particles don't need more than
    static let effectRenderingScale: CGFloat = 1.33
}

/// Whether reactions keep still, as Reduce Motion asks
@MainActor
enum AgentReactionMotion {
    /// Stands in for the system setting in tests
    static var isReducedOverride: Bool?

    static var isReduced: Bool {
        isReducedOverride ?? UIAccessibility.isReduceMotionEnabled
    }
}

/// The reactions' animations, each read from the bundle and decompressed once per session, and their still frames,
/// each drawn once per session
@MainActor
enum AgentReactionAnimations {
    private static var sources: [String: LottieAnimationSource] = [:]
    private static var stills: [String: UIImage] = [:]
    private static var isPrewarmed = false

    static func getName(_ animation: AgentReactionAnimation, of feedback: ApiAgentV2AnswerFeedback) -> String {
        let emoji = switch feedback {
        case .like: "heart"
        case .dislike: "heart_broken"
        }
        return "agent_reaction_\(emoji)_\(animation.rawValue)"
    }

    static func getSource(_ animation: AgentReactionAnimation, of feedback: ApiAgentV2AnswerFeedback) -> LottieAnimationSource? {
        let name = getName(animation, of: feedback)
        if let source = sources[name] {
            return source
        }
        guard let data = decode(named: name) else { return nil }
        let source = LottieAnimationSource.data(data, cacheKey: name)
        sources[name] = source
        return source
    }

    /// Decompresses and parses every reaction animation off the main thread, so that the cloud opens and the
    /// reactions play without parsing any
    static func prewarm() {
        guard !isPrewarmed else { return }
        isPrewarmed = true
        let names = ApiAgentV2AnswerFeedback.reactionOrder.flatMap { feedback in
            AgentReactionAnimation.allCases.map { getName($0, of: feedback) }
        }
        Task.detached(priority: .utility) {
            let decoded = names.compactMap { name in AgentReactionAnimations.decode(named: name).map { (name, $0) } }
            await MainActor.run {
                for (name, data) in decoded where AgentReactionAnimations.sources[name] == nil {
                    AgentReactionAnimations.sources[name] = .data(data, cacheKey: name)
                }
                for (name, data) in decoded {
                    // The player parses an animation off the main thread and keeps the parsed animation by its key
                    let loader = LottieAnimationView(frame: .zero)
                    Task {
                        try? await loader.setAnimation(source: .data(data, cacheKey: name), playbackMode: .still(position: .begin))
                    }
                }
            }
        }
    }

    /// A frame of `animation` drawn in a box of `boxSize`, cut to its middle `size`
    static func getStill(
        _ animation: AgentReactionAnimation,
        of feedback: ApiAgentV2AnswerFeedback,
        at position: LottieAnimationStartingPosition,
        boxSize: CGFloat,
        size: CGFloat
    ) -> UIImage {
        let key = "\(getName(animation, of: feedback)) \(position) \(boxSize) \(size)"
        if let image = stills[key] {
            return image
        }
        let renderer = LottieAnimationView(frame: CGRect(x: 0, y: 0, width: boxSize, height: boxSize))
        renderer.reducesRenderingScaleInLowPowerMode = false
        guard let source = getSource(animation, of: feedback),
              (try? renderer.setAnimationSynchronously(
                  source: source,
                  playbackMode: .still(position: position),
                  displayFirstFrameSynchronously: true
              )) != nil,
              let frame = renderer.image else {
            return UIImage()
        }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = frame.scale
        let inset = (boxSize - size) / 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { _ in
            frame.draw(in: CGRect(x: -inset, y: -inset, width: boxSize, height: boxSize))
        }
        stills[key] = image
        return image
    }

    /// The animation's JSON: the bundle's gzip file without its header, inflated
    nonisolated static func decode(named name: String) -> Data? {
        guard let url = AirBundle.url(forResource: name, withExtension: "tgs"),
              let file = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return inflateGzip(file) ?? file
    }

    /// The content of gzip `data` (RFC 1952), or nil when it isn't gzip
    nonisolated static func inflateGzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < bytes.count, bytes[offset] != 0 {
                offset += 1
            }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}

/// A reaction's emoji: one of its Telegram animations playing once and resting on its last frame, or a still frame of
/// one
@MainActor
final class AgentReactionEmojiView: UIView {
    /// The reaction the view shows
    private(set) var feedback: ApiAgentV2AnswerFeedback?
    /// The animation the view plays, or shows a frame of
    private(set) var animation: AgentReactionAnimation?
    private(set) var isPlaying = false
    /// The side of the square the animations play in
    let boxSize: CGFloat
    /// The pixels per point the animations render at, the screen's by default
    var renderingScale: CGFloat {
        get { lottieView.renderingScale }
        set { lottieView.renderingScale = newValue }
    }

    /// Holds the animation, which fades as the view goes over to another drawing
    private let drawingView = UIView()
    private let lottieView = LottieAnimationView()
    /// Another drawing of the emoji under the view's own, such as the cloud's, which the view goes over to
    private var crossFadeView: UIImageView?
    private var loadedName: String?
    private var playID = 0

    init(boxSize: CGFloat) {
        self.boxSize = boxSize
        super.init(frame: CGRect(x: 0, y: 0, width: boxSize, height: boxSize))
        isUserInteractionEnabled = false
        drawingView.isUserInteractionEnabled = false
        drawingView.frame = bounds
        addSubview(drawingView)
        lottieView.isUserInteractionEnabled = false
        lottieView.frame = drawingView.bounds
        drawingView.addSubview(lottieView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawingView.frame = bounds
        lottieView.frame = drawingView.bounds
        if let crossFadeView {
            crossFadeView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    /// Readies another drawing of the emoji, `image` in a square of `side` around the view's middle in its own
    /// coordinates, for the view to go over to with `setCrossFade(_:)`, starting from its own drawing
    func prepareCrossFade(to image: UIImage, side: CGFloat) {
        let view = crossFadeView ?? UIImageView()
        if crossFadeView == nil {
            view.isUserInteractionEnabled = false
            view.contentMode = .scaleToFill
            insertSubview(view, belowSubview: drawingView)
            crossFadeView = view
        }
        view.image = image
        view.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        view.center = CGPoint(x: bounds.midX, y: bounds.midY)
        setCrossFade(0)
    }

    /// How far the view has gone from its own drawing, 0, over to the other one, 1. Each shows fully for half of
    /// the way, the other one under the view's own, so the emoji never thins as the two change places.
    func setCrossFade(_ fraction: CGFloat) {
        guard let crossFadeView else { return }
        let fraction = min(max(fraction, 0), 1)
        drawingView.alpha = min(1, 2 * (1 - fraction))
        crossFadeView.alpha = min(1, 2 * fraction)
    }

    /// How far the view has gone over to the other drawing, nil without one
    var crossFade: CGFloat? {
        guard let crossFadeView else { return nil }
        return crossFadeView.alpha >= 1 ? 1 - drawingView.alpha / 2 : crossFadeView.alpha / 2
    }

    /// The frame the view shows at the moment, still or playing
    var currentDrawing: UIImage? {
        lottieView.image
    }

    /// Where the view's box shows on screen now, in its window's coordinates
    var presentedFrameInWindow: CGRect? {
        guard let window else { return nil }
        let presentedLayer = layer.presentation() ?? layer
        let rootLayer = window.layer.presentation() ?? window.layer
        return presentedLayer.convert(bounds, to: rootLayer)
    }

    /// Rests on a frame of `animation`, drawn once per session
    func showStill(_ animation: AgentReactionAnimation, of feedback: ApiAgentV2AnswerFeedback, at position: LottieAnimationStartingPosition) {
        playID += 1
        isPlaying = false
        self.feedback = feedback
        self.animation = animation
        if loadedName != nil {
            lottieView.reset()
            loadedName = nil
        }
        lottieView.image = AgentReactionAnimations.getStill(animation, of: feedback, at: position, boxSize: boxSize, size: boxSize)
    }

    /// Plays `animation` once from its start and rests on its last frame
    func play(_ animation: AgentReactionAnimation, of feedback: ApiAgentV2AnswerFeedback, completion: (() -> Void)? = nil) {
        playID += 1
        let playID = playID
        self.feedback = feedback
        self.animation = animation
        let name = AgentReactionAnimations.getName(animation, of: feedback)
        if loadedName != name {
            guard let source = AgentReactionAnimations.getSource(animation, of: feedback),
                  (try? lottieView.setAnimationSynchronously(
                      source: source,
                      playbackMode: .still(position: .begin),
                      displayFirstFrameSynchronously: true
                  )) != nil else {
                loadedName = nil
                isPlaying = false
                completion?()
                return
            }
            loadedName = name
        }
        isPlaying = true
        let didStart = lottieView.playOnce { [weak self] in
            guard let self, self.playID == playID else { return }
            self.isPlaying = false
            completion?()
        }
        if !didStart {
            isPlaying = false
            completion?()
        }
    }

    /// Shows nothing
    func clear() {
        playID += 1
        isPlaying = false
        feedback = nil
        animation = nil
        lottieView.reset()
        loadedName = nil
    }
}

/// An animation that plays once over the window, above the chat and an open menu, where nothing clips it, following a
/// point such as the answer's corner, and goes when it ends
@MainActor
final class AgentReactionEffect {
    static let fadeDuration: TimeInterval = 0.2

    let view: AgentReactionEmojiView
    private let getCenter: () -> CGPoint?
    private var lastCenter: CGPoint
    private var subscriptionID: UUID?
    private(set) var isFinished = false

    /// Plays `animation` in a square of `size` centred on the point `getCenter` gives, in `window`'s coordinates, over
    /// the window's other views; a point that goes away keeps the last one
    @discardableResult
    static func play(
        _ animation: AgentReactionAnimation,
        of feedback: ApiAgentV2AnswerFeedback,
        size: CGFloat,
        in window: UIWindow,
        center getCenter: @escaping () -> CGPoint?
    ) -> AgentReactionEffect? {
        guard let center = getCenter() else { return nil }
        let effect = AgentReactionEffect(size: size, center: center, getCenter: getCenter)
        let view = effect.view
        window.addSubview(view)
        effect.subscriptionID = AgentDisplayLinkDriver.shared.add { [effect] in
            effect.follow()
        }
        view.play(animation, of: feedback) { [effect] in
            effect.finish()
        }
        return effect
    }

    private init(size: CGFloat, center: CGPoint, getCenter: @escaping () -> CGPoint?) {
        view = AgentReactionEmojiView(boxSize: size)
        view.renderingScale = AgentReactionEmojiMetrics.effectRenderingScale
        self.getCenter = getCenter
        lastCenter = center
        view.center = center
    }

    private func follow() {
        // A window that goes away takes the effect with it
        guard view.window != nil else {
            finish()
            return
        }
        if let center = getCenter() {
            lastCenter = center
        }
        view.center = lastCenter
    }

    /// Fades the view out and removes it
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        if let subscriptionID {
            AgentDisplayLinkDriver.shared.remove(subscriptionID)
        }
        subscriptionID = nil
        let view = view
        UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: [.beginFromCurrentState]) {
            view.alpha = 0
        } completion: { _ in
            view.removeFromSuperview()
        }
    }
}
