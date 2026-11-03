import UIKit
import UIComponents
import WalletContext

/// A chat screen whose composer the Agent list's question field turns into during a push or pop
@MainActor
public protocol AgentComposerHandoffTarget: AnyObject {
    /// Hides the screen's own composer while the list's field stands in for it
    func setComposerHandoffHidden(_ isHidden: Bool)
    /// Where the composer's field rests, in `window`'s coordinates, for the list's field to land on
    func getComposerHandoffFrame(in window: UIWindow) -> CGRect?
}

public extension AgentComposerHandoffTarget {
    func getComposerHandoffFrame(in window: UIWindow) -> CGRect? { nil }
}

/// The Agent list's bottom bar: the question field and the microphone beside the root toolbar's search circle.
///
/// The root lays the bar over its toolbar and can host the bar's glass in the toolbar's glass container, so the field,
/// the microphone and the search circle are one piece of Liquid Glass that flows together where they meet.
/// `morphProgress` splits the toolbar's search field into the search circle and the question field while paging to
/// the Agent tab: the question field starts as the search field's glass and parts from the circle the search field
/// shrinks into, and the microphone's circle takes the trailing button's place, the plus giving way to the microphone.
/// The bar follows the progress on a spring, so the pieces swell through the morph and settle with a slight bounce,
/// as in Telegram.
/// `expansion` widens the field to a thread composer's full width, for focus and for the push into a chat.
@MainActor
public final class AgentListBottomBar: UIView {
    public nonisolated static let height: CGFloat = 48
    /// Glass pieces of the bar and the toolbar closer than this flow into each other. The toolbars' resting gaps,
    /// 8 pt and more, stay apart.
    public nonisolated static let glassMergeSpacing: CGFloat = 6
    /// How much the bar's glass swells at the middle of the morph
    nonisolated static let morphSwell: CGFloat = 0.2
    /// The gap between the search circle and the field
    static let spacing: CGFloat = 12

    /// The widest the root toolbar gets on any tab: as wide as a chat's composer row, the chat's content column less
    /// `sideInset` on each side, so the field lands on the composer at its width. Only wide screens reach it.
    public static func getMaximumToolbarWidth(sideInset: CGFloat) -> CGFloat {
        AgentContentLayout.maxContentWidth - 2 * sideInset
    }
    /// Telegram's bar items' spring: the morph keeps pace with the page sliding in and settles with a little overshoot.
    /// Tied to the spring's progress, the swell peaks about 0.1 s in and dips 2.5% under the size as the spring
    /// overshoots, about 0.3 s in, as Telegram's glass does.
    private static let springResponse = GlassMotion.transition.response
    private static let springDamping = GlassMotion.transition.dampingRatio

    public var onEditingChange: ((Bool) -> Void)?
    /// Editing changes for the view that hosts the bar, which moves it with the keyboard
    public var onHostEditingChange: ((Bool) -> Void)?
    public var onSend: ((String) -> Void)?
    /// The progress the bar shows on each frame of its spring, for a host whose own pieces morph along
    public var onMorphFrame: ((CGFloat) -> Void)?
    /// The field grew or shrank with its text; it grows upward, past the bar's top
    var onFieldHeightChange: (() -> Void)?

    /// The field's height; a field taller than the bar reaches above it
    public var fieldHeight: CGFloat { max(Self.height, composerView.inputHeight) }

    /// The field's glass in the bar's coordinates
    public var fieldFrame: CGRect {
        composerView.convert(composerView.inputBackgroundFrame, to: self)
    }

    let composerView = AgentComposerView(style: .bare)
    private let plusImageView = UIImageView()
    /// The shown progress, which follows the requested one on a spring and may overshoot it
    public private(set) var morphProgress: CGFloat = 1
    private var targetMorphProgress: CGFloat = 1
    private var morphVelocity: CGFloat = 0
    private var lastMorphFrameTime: CFTimeInterval?
    private lazy var morphClock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.stepMorph() }
    /// How much wider than its trailing button the toolbar's buttons are. The field starts beside them, as the
    /// toolbar's search field does, and grows over them as they fold into the trailing button.
    public var toolbarActionsWidth: CGFloat = 0 {
        didSet {
            if toolbarActionsWidth != oldValue { setNeedsLayout() }
        }
    }
    /// How far the field is widened to a thread composer's width, as `setExpansion` set it
    public private(set) var expansion: CGFloat = 0
    private weak var glassHost: UIView?

    public var isEditing: Bool { composerView.isTextInputActive }

    var draftText: String {
        composerView.draftText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The bar's glass that lives in the host's container and takes touches there
    public var hostedGlassViews: [UIView] {
        guard glassHost != nil, !isHidden, morphProgress > 0.99 else { return [] }
        return composerView.hostedGlassViews
    }

    public override var isHidden: Bool {
        didSet { composerView.isGlassHidden = isHidden }
    }

    public override var alpha: CGFloat {
        didSet { composerView.glassAlpha = alpha }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        accessibilityIdentifier = "AgentThreadComposer"
        composerView.translatesAutoresizingMaskIntoConstraints = true
        composerView.setSendEnabled(false)
        composerView.onDraftTextChanged = { [weak self] in
            guard let self else { return }
            composerView.setSendEnabled(!draftText.isEmpty)
        }
        composerView.onSend = { [weak self] in self?.send() }
        composerView.onBeginEditing = { [weak self] in
            self?.onEditingChange?(true)
            self?.onHostEditingChange?(true)
        }
        composerView.onEndEditing = { [weak self] in
            self?.onEditingChange?(false)
            self?.onHostEditingChange?(false)
        }
        composerView.onLayoutHeightChanged = { [weak self] in
            self?.setNeedsLayout()
            self?.onFieldHeightChange?()
        }
        addSubview(composerView)

        plusImageView.image = UIImage.airBundle("UniversalSearchPlus").withRenderingMode(.alwaysTemplate)
        plusImageView.tintColor = .label
        plusImageView.contentMode = .center
        plusImageView.isUserInteractionEnabled = false
        plusImageView.isAccessibilityElement = false
        addSubview(plusImageView)
        applyMorph()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Hosted glass takes its touches in the host's container
        guard glassHost == nil, morphProgress > 0.99 else { return false }
        return composerView.frame.insetBy(dx: 0, dy: -6).contains(point)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { settleMorph() }
    }

    /// Places the field's and the microphone's glass in `host`, the content view of the toolbar's glass container,
    /// so they merge with the toolbar's glass. Nil gives the bar its own container again.
    public func setGlassHost(_ host: UIView?) {
        glassHost = host
        composerView.setGlassHost(host)
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// 0: the field and the microphone's circle are the root toolbar's search field and trailing button; 1: the
    /// Agent list's field and microphone
    public func setMorphProgress(_ progress: CGFloat) {
        let progress = min(1, max(0, progress))
        guard progress != targetMorphProgress else { return }
        targetMorphProgress = progress
        hasFolded = false
        guard window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled else {
            settleMorph()
            return
        }
        if !morphClock.isRunning {
            lastMorphFrameTime = nil
            morphClock.start()
        }
    }

    /// 0: the list's field beside the search circle; 1: a thread composer's full-width field. A spring may carry it a
    /// little past either end.
    public func setExpansion(_ expansion: CGFloat) {
        let expansion = min(1.15, max(-0.15, expansion))
        guard expansion != self.expansion else { return }
        self.expansion = expansion
        setNeedsLayout()
    }

    /// Search opening over the list: 0 is the bar as it rests; 1 has the field flown off past the trailing edge and
    /// the microphone turned into the search's close cross, which the search's own button then takes over. A spring
    /// may carry it a little past either end.
    public func setSearchHandoff(_ progress: CGFloat) {
        let flight = min(1.1, max(-0.1, progress))
        composerView.fieldHandoffOffset = flight * (bounds.width + Self.height)
        composerView.actionGlyphSwap = max(0, progress)
    }

    public func focus() {
        composerView.setDraftText(composerView.draftText ?? "", focus: true)
    }

    func clearDraft() {
        composerView.clearDraft()
        composerView.setSendEnabled(false)
    }

    public func resignEditing() {
        composerView.endEditing(true)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        // Positions stop at the ends; only the swell carries the spring's overshoot, so the field never reaches past
        // the search field it comes out of while it settles
        let shown = shownMorphProgress
        let progress = min(1, max(0, shown))
        // The field starts where the toolbar's search field is, beside the trailing button the microphone's circle
        // stands in for, and its leading edge parts from the circle the search field shrinks into
        let listX = Self.height + Self.spacing
        let restingX = listX * progress
        let minX = restingX - restingX * expansion
        let maxX = width
        // The field rests on the bar's bottom, which the host places as it places its search field, above the
        // keyboard or not
        let fieldHeight = self.fieldHeight
        composerView.frame = getDirectionalFrame(CGRect(
            x: minX,
            y: bounds.maxY - fieldHeight,
            width: max(Self.height, maxX - minX),
            height: fieldHeight
        ))
        composerView.actionCircleHold = 1 - progress
        composerView.fieldTrailingReserve = toolbarActionsWidth * (1 - Self.getSearchCircleCollapse(at: progress))
        composerView.glassScale = Self.swell(at: min(1.15, max(-0.1, shown)))
        composerView.layoutIfNeeded()
        composerView.layoutHostedGlass()
        plusImageView.frame = getDirectionalFrame(CGRect(
            x: width - Self.height,
            y: bounds.maxY - Self.height,
            width: Self.height,
            height: Self.height
        ))
    }

    /// How far the toolbar's search field has shrunk into the search circle at `progress` of the morph. It shrinks
    /// under the question field ahead of the field's leading edge, so the two stay one piece of glass through the first
    /// half of the morph and then part, the gap between them opening as the field settles.
    public nonisolated static func getSearchCircleCollapse(at progress: CGFloat) -> CGFloat {
        1 - pow(1 - min(1, max(0, progress)), 3.5)
    }

    /// The swell of a morphing piece: largest midway, slightly under its size while the spring overshoots
    public nonisolated static func swell(at progress: CGFloat) -> CGFloat {
        let swell = 1 + morphSwell * 4 * progress * (1 - progress)
        return min(1 + morphSwell, max(0.9, swell))
    }

    private func getDirectionalFrame(_ frame: CGRect) -> CGRect {
        guard effectiveUserInterfaceLayoutDirection == .rightToLeft else { return frame }
        return CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private func stepMorph() {
        let now = CACurrentMediaTime()
        let elapsed = lastMorphFrameTime.map { min(1.0 / 30, now - $0) } ?? 1.0 / 60
        lastMorphFrameTime = now
        let omega = 2 * .pi / Self.springResponse
        // Substeps keep the integration stable on long frames
        let steps = 4
        let dt = CGFloat(elapsed) / CGFloat(steps)
        for _ in 0..<steps {
            let acceleration = -omega * omega * (morphProgress - targetMorphProgress)
                - 2 * Self.springDamping * omega * morphVelocity
            morphVelocity += acceleration * dt
            morphProgress += morphVelocity * dt
        }
        // Once folded back into the toolbar's search field and button, the bar stays there: swinging past would hand
        // them back and forth between the bar and the toolbar. The spring runs on for the toolbar's pieces, which
        // settle with the same slight bounce as on the way in.
        if targetMorphProgress <= 0 && morphProgress <= 0 {
            hasFolded = true
        }
        let isAtRest = abs(morphProgress - targetMorphProgress) < 0.0005 && abs(morphVelocity) < 0.005
        if isAtRest {
            settleMorph()
            return
        }
        applyMorph()
    }

    /// The bar went back into the toolbar's search field and button during the current fold
    private var hasFolded = false

    /// The progress the bar's pieces and the host follow: after folding, it doesn't come back out of the toolbar
    private var shownMorphProgress: CGFloat {
        hasFolded ? min(0, morphProgress) : morphProgress
    }

    private func settleMorph() {
        morphClock.stop()
        morphVelocity = 0
        morphProgress = targetMorphProgress
        applyMorph()
    }

    private func applyMorph() {
        let shown = shownMorphProgress
        let progress = min(1, max(0, shown))
        // The field's own content appears in the second half, as the field parts from the circle; the plus shrinks
        // away on the microphone's circle before the microphone grows in with it, as the header capsules swap their
        // content
        let hidden = GlassMotion.matchScale
        let plusSwap = min(1, progress / 0.35)
        let plusScale = 1 + (hidden - 1) * plusSwap
        plusImageView.alpha = 1 - plusSwap
        // The plus turns a little as it goes, and back as it returns
        plusImageView.transform = progress == 0
            ? .identity
            : CGAffineTransform(rotationAngle: .pi / 4 * progress).scaledBy(x: plusScale, y: plusScale)
        let content = max(0, (progress - 0.45) / 0.55)
        composerView.contentAlpha = content
        composerView.actionContentScale = hidden + (1 - hidden) * content
        composerView.isHeightUpdateSuspended = targetMorphProgress < 1 || morphProgress < 0.99
        composerView.isUserInteractionEnabled = morphProgress > 0.99
        accessibilityElementsHidden = morphProgress < 0.99
        setNeedsLayout()
        layoutIfNeeded()
        onMorphFrame?(shown)
    }

    private func send() {
        let text = draftText
        guard !text.isEmpty else { return }
        onSend?(text)
    }
}
