import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

enum AgentThreadRowMetrics {
    static let height: CGFloat = 82
    static let horizontalInset: CGFloat = 16
    static let avatarSize: CGFloat = 45
    static let avatarTop: CGFloat = 11
    static let textLeading: CGFloat = 73
    static let titleTop: CGFloat = 10
    static let titleLineHeight: CGFloat = 22
    static let previewTop: CGFloat = 34
    static let previewLineHeight: CGFloat = 19
    static let previewBottomInset: CGFloat = 10
    static let pinWidth: CGFloat = 11
    /// The design draws the pin as a 13 pt symbol on the title's text line, where it sits on the baseline: its head
    /// level with the title's capitals and its needle past the baseline. Centred in the line it would sit higher.
    static let pinVerticalOffset: CGFloat = 8.0 / 3.0
    static let pinSpacing: CGFloat = 6
    static let timeSpacing: CGFloat = 8
    /// The unread dot at the end of the preview, centered on its two lines
    static let unreadDotSize: CGFloat = 11
    static let unreadDotSpacing: CGFloat = 8
    static let unreadDotTopOffset: CGFloat = 14
    /// Telegram's unread counter, which takes the dot's place: a capsule as tall as this, 5 pt wider than its digits on
    /// each side and never narrower than it is tall
    static let unreadCounterHeight: CGFloat = 20
    static let unreadCounterHorizontalPadding: CGFloat = 10
    static let unreadCounterFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    /// Telegram's chat list typing status: the indicator starts 3 pt before the preview and the text 24 pt after it
    static let activityIndicatorLeading: CGFloat = -3

    /// As thick as the system lists' separators, such as the token list's: a point from iOS 26, a pixel before
    static func getSeparatorThickness(displayScale: CGFloat) -> CGFloat {
        if #available(iOS 26, *) { return 1 }
        return 1 / max(1, displayScale)
    }

    static var separatorColor: UIColor {
        IOS_26_MODE_ENABLED ? .separator : .air.separator
    }

    static var activityAttributes: [NSAttributedString.Key: Any] {
        // The gradient fills the drawn text, so its own color only needs to be opaque
        makeLineAttributes(font: .systemFont(ofSize: 15, weight: .medium), lineHeight: previewLineHeight, color: .black)
    }

    static var titleAttributes: [NSAttributedString.Key: Any] {
        makeLineAttributes(font: .systemFont(ofSize: 17, weight: .semibold), lineHeight: titleLineHeight, color: .label)
    }

    static var timeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: secondaryTextColor,
        ]
    }

    /// Telegram's chat list thumbnail before the preview: 18 pt, as for its default 17 pt text, with rounded corners
    /// and 5 pt to the text
    static let previewImageSize: CGFloat = 18
    static let previewImageSpacing: CGFloat = 5
    static let previewImageCornerRadius: CGFloat = 2

    /// The preview's text, its first line starting `firstLineIndent` in
    static func makePreviewAttributes(firstLineIndent: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes = makeLineAttributes(font: .systemFont(ofSize: 15), lineHeight: previewLineHeight, color: secondaryTextColor)
        if firstLineIndent > 0, let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            paragraph.firstLineHeadIndent = firstLineIndent
            attributes[.paragraphStyle] = paragraph
        }
        return attributes
    }

    /// Text on lines of exactly `lineHeight`, cut off with an ellipsis
    private static func makeLineAttributes(font: UIFont, lineHeight: CGFloat, color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: color]
    }

    static let secondaryTextColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "#8D8D93") : UIColor(hex: "#8E8E93")
    }

    static let headerTextColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.6)
            : UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.6)
    }
}

/// Telegram's chat list swipe: actions are revealed only by a swipe that starts near the trailing edge, so swipes
/// elsewhere page between the tabs
enum AgentThreadSwipeMetrics {
    static let buttonSize: CGFloat = 50
    static let buttonSpacing: CGFloat = 10
    static let edgeInset: CGFloat = 10
    static let cardCornerRadius: CGFloat = 26

    static func getEdgeZoneWidth(for width: CGFloat) -> CGFloat {
        min(80, max(22, width / 6))
    }

    static let cardColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(hex: "#F2F2F7")
    }
}

/// The long-press menu lifts the row into a card inset from the screen edges, over the blurred list, with the menu
/// hanging under it
enum AgentThreadMenuMetrics {
    static let cardInset: CGFloat = 16
    static let cardCornerRadius: CGFloat = 26
    static let menuSpacing: CGFloat = 12
    static let menuCornerRadius: CGFloat = 34
    static let backdropBlurRadius: CGFloat = 24
    static let backdropDimAlpha: CGFloat = 0.21
    static let backdropTint = UIColor(red: 24 / 255, green: 19 / 255, blue: 43 / 255, alpha: 1)
}

class AgentThreadRowCell: UICollectionViewListCell {
    let avatarView = AgentThreadAvatarView()
    let titleLabel = UILabel()
    let previewLabel = UILabel()
    let timeLabel = UILabel()
    let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    /// The row's horizontal extent in `contentView`, inset while the row is lifted into the menu's card
    let rowLayoutGuide = UILayoutGuide()
    /// The line under a row that another row of its section follows, from the text's leading edge to the row's end
    let separatorView = UIView()
    /// Telegram's unread mark, at the end of the preview's lines
    private let unreadBadge = AgentUnreadBadgeView()
    /// Telegram's chat list thumbnail, centred on the preview's first line, which alone makes room for it. It shows once
    /// its picture has loaded, and goes with the preview when the Agent's status takes the preview's place.
    private let previewImageView = WImageView()
    private var previewImageURL: URL?
    private var isPreviewImageShown = false {
        didSet {
            guard isPreviewImageShown != oldValue else { return }
            previewImageView.isHidden = !isPreviewImageShown
            updatePreviewLeadingViews()
        }
    }
    /// The label of a chat with support, before the preview's text and after its picture, as in Classic
    let supportLabelView = AgentSupportLabelView()
    private var supportLabelLeadingConstraint: NSLayoutConstraint!
    private var supportLabelWidth: CGFloat = 0
    /// The support label's look; nil hides it
    var supportLabelStyle: AgentSupportPresentation.LabelStyle? {
        didSet {
            guard supportLabelStyle != oldValue else { return }
            supportLabelView.isHidden = supportLabelStyle == nil
            if let supportLabelStyle {
                supportLabelView.configure(style: supportLabelStyle)
                supportLabelWidth = ceil(supportLabelView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width)
            }
            updatePreviewLeadingViews()
        }
    }
    /// The touched row's highlight, as in the wallet's token list: it comes in quickly as the finger lands and fades
    /// slowly. It lies under `contentView`, so the press that shrinks the row's content for the menu leaves it whole.
    private let highlightView = UIView()
    private var isHighlightShown = false
    private var isTouchHighlighted = false
    override var isHighlighted: Bool {
        didSet { updateHighlight() }
    }
    /// Keeps the row lit while the chat it opened slides in, as in Telegram's chat list; letting go fades it
    var isHighlightHeld = false {
        didSet {
            guard isHighlightHeld != oldValue else { return }
            updateHighlight()
        }
    }
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var previewTrailingConstraint: NSLayoutConstraint!
    private var rowLeadingConstraint: NSLayoutConstraint!
    private var rowTrailingConstraint: NSLayoutConstraint!

    /// Extra room at the end of the preview, for a badge beside it
    var previewTrailingInset: CGFloat = 0 {
        didSet { previewTrailingConstraint.constant = -AgentThreadRowMetrics.horizontalInset - previewTrailingInset }
    }

    var rowContentInset: CGFloat = 0 {
        didSet {
            rowLeadingConstraint.constant = rowContentInset
            rowTrailingConstraint.constant = -rowContentInset
        }
    }

    var isBottomSeparatorShown = false {
        didSet { updateSeparatorAlpha() }
    }

    /// How far the row under this one is lifted into a card or highlighted, 0 to 1: as in the system's lists, the line
    /// between them gives way
    var followingRowEmphasis: CGFloat = 0 {
        didSet { updateSeparatorAlpha() }
    }

    /// Called as the row's own emphasis changes, so the list can let the line above it give way
    var onEmphasisChange: ((CGFloat) -> Void)?

    /// How far the row is lifted into a card or highlighted, 0 to 1
    private(set) var emphasis: CGFloat = 0

    /// The unread mark at the end of the preview's lines, which the preview keeps clear of; nil hides it
    var unreadMark: AgentUnreadMark? {
        didSet {
            guard unreadMark != oldValue else { return }
            unreadBadge.isHidden = unreadMark == nil
            if case .count(let text) = unreadMark {
                unreadBadge.countText = text
            } else {
                unreadBadge.countText = nil
            }
            previewTrailingInset = unreadMark == nil
                ? 0
                : unreadBadge.intrinsicContentSize.width + AgentThreadRowMetrics.unreadDotSpacing
        }
    }

    /// How far the row is lifted off the list into a card, 0 to 1. The card takes the place of the row's separator.
    var liftProgress: CGFloat = 0 {
        didSet {
            updateSeparatorAlpha()
            updateHighlight()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureRowViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isPinIconVisible: Bool = false {
        didSet {
            pinView.isHidden = !isPinIconVisible
            titleLeadingConstraint.constant = isPinIconVisible
                ? AgentThreadRowMetrics.pinWidth + AgentThreadRowMetrics.pinSpacing
                : 0
        }
    }

    func setTexts(title: String, preview: String?, time: String?) {
        titleLabel.attributedText = NSAttributedString(string: title, attributes: AgentThreadRowMetrics.titleAttributes)
        previewLabel.attributedText = preview.map(makePreviewText)
        previewLabel.isHidden = preview == nil
        timeLabel.attributedText = time.map { NSAttributedString(string: $0, attributes: AgentThreadRowMetrics.timeAttributes) }
        timeLabel.isHidden = time == nil
    }

    /// Shows the picture at `url` before the preview once it has loaded; nil shows none
    func setPreviewImage(url: URL?) {
        guard url != previewImageURL else { return }
        previewImageURL = url
        isPreviewImageShown = false
        previewImageView.loadImage(url: url) { [weak self] didLoad in
            guard let self, self.previewImageURL == url else { return }
            self.isPreviewImageShown = didLoad
        }
    }

    private func makePreviewText(_ preview: String) -> NSAttributedString {
        let imageIndent = isPreviewImageShown ? AgentThreadRowMetrics.previewImageSize + AgentThreadRowMetrics.previewImageSpacing : 0
        let labelIndent = supportLabelStyle == nil ? 0 : supportLabelWidth + AgentSupportLabelView.spacing
        return NSAttributedString(
            string: preview,
            attributes: AgentThreadRowMetrics.makePreviewAttributes(firstLineIndent: imageIndent + labelIndent)
        )
    }

    private func updatePreviewLeadingViews() {
        supportLabelLeadingConstraint.constant = isPreviewImageShown
            ? AgentThreadRowMetrics.previewImageSize + AgentThreadRowMetrics.previewImageSpacing
            : 0
        if let preview = previewLabel.attributedText?.string {
            previewLabel.attributedText = makePreviewText(preview)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let thickness = AgentThreadRowMetrics.getSeparatorThickness(displayScale: traitCollection.displayScale)
        let leading = AgentThreadRowMetrics.textLeading
        let trailing = AgentThreadRowMetrics.horizontalInset
        let width = max(0, bounds.width - leading - trailing)
        separatorView.frame = CGRect(
            x: effectiveUserInterfaceLayoutDirection == .rightToLeft ? trailing : leading,
            y: bounds.height - thickness,
            width: width,
            height: thickness
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.displayScale != previousTraitCollection?.displayScale {
            setNeedsLayout()
        }
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        // Attributed colors are resolved when drawn, but re-applying keeps them in sync with the trait
        if let title = titleLabel.attributedText?.string {
            setTexts(title: title, preview: previewLabel.attributedText?.string, time: timeLabel.attributedText?.string)
        }
    }

    private func updateSeparatorAlpha() {
        let ownEmphasis = max(min(1, max(0, liftProgress)), isHighlightShown ? 1 : 0)
        if ownEmphasis != emphasis {
            emphasis = ownEmphasis
            onEmphasisChange?(ownEmphasis)
        }
        separatorView.alpha = isBottomSeparatorShown ? 1 - max(ownEmphasis, min(1, max(0, followingRowEmphasis))) : 0
    }

    // The list highlights a row only once it is sure the touch isn't a scroll; the token list's rows light up as the
    // finger lands, and a scroll that starts takes the highlight away again
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchHighlighted = true
        updateHighlight()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        isTouchHighlighted = false
        updateHighlight()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouchHighlighted = false
        updateHighlight()
        super.touchesCancelled(touches, with: event)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isTouchHighlighted = false
        isHighlightHeld = false
        updateHighlight()
    }

    /// Lets the highlight go, for a touch that turned out not to be a tap
    func cancelHighlight() {
        isTouchHighlighted = false
        isHighlighted = false
        updateHighlight()
    }

    private func updateHighlight() {
        setHighlightShown((isTouchHighlighted || isHighlighted || isHighlightHeld) && liftProgress == 0)
    }

    /// Shows or fades the row's highlight with the token list's timing. A row lifted into the menu's card lets it go
    /// quickly, as the card takes over.
    private func setHighlightShown(_ isShown: Bool) {
        guard isShown != isHighlightShown else { return }
        isHighlightShown = isShown
        guard window != nil, UIView.areAnimationsEnabled else {
            highlightView.alpha = isShown ? 1 : 0
            updateSeparatorAlpha()
            return
        }
        // The lines above and below the row fade with its highlight
        UIView.animate(
            withDuration: isShown ? 0.1 : (liftProgress > 0 ? 0.15 : 0.5),
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveLinear]
        ) {
            self.highlightView.alpha = isShown ? 1 : 0
            self.updateSeparatorAlpha()
        }
    }

    private func configureRowViews() {
        var background = UIBackgroundConfiguration.listPlainCell()
        background.backgroundColor = .clear
        backgroundConfiguration = background
        isAccessibilityElement = true
        accessibilityTraits = .button

        separatorView.backgroundColor = AgentThreadRowMetrics.separatorColor
        separatorView.isUserInteractionEnabled = false
        separatorView.alpha = 0
        addSubview(separatorView)

        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.backgroundColor = .air.highlight
        highlightView.isUserInteractionEnabled = false
        highlightView.alpha = 0
        insertSubview(highlightView, belowSubview: contentView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        pinView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.numberOfLines = 2
        timeLabel.textAlignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        pinView.tintColor = AgentThreadRowMetrics.secondaryTextColor
        pinView.contentMode = .center
        pinView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        pinView.isHidden = true

        contentView.addLayoutGuide(rowLayoutGuide)
        contentView.addSubview(avatarView)
        contentView.addSubview(pinView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(previewLabel)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = AgentThreadRowMetrics.previewImageCornerRadius
        previewImageView.isHidden = true
        previewImageView.isAccessibilityElement = false
        previewLabel.addSubview(previewImageView)
        supportLabelView.translatesAutoresizingMaskIntoConstraints = false
        supportLabelView.isHidden = true
        previewLabel.addSubview(supportLabelView)
        supportLabelLeadingConstraint = supportLabelView.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor)
        unreadBadge.translatesAutoresizingMaskIntoConstraints = false
        unreadBadge.isHidden = true
        unreadBadge.setContentHuggingPriority(.required, for: .horizontal)
        unreadBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(unreadBadge)

        rowLeadingConstraint = rowLayoutGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        rowTrailingConstraint = rowLayoutGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: pinView.leadingAnchor)
        previewTrailingConstraint = previewLabel.trailingAnchor.constraint(
            equalTo: rowLayoutGuide.trailingAnchor,
            constant: -AgentThreadRowMetrics.horizontalInset
        )
        let height = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: AgentThreadRowMetrics.height)
        let inset = AgentThreadRowMetrics.horizontalInset
        NSLayoutConstraint.activate([
            height,
            rowLeadingConstraint,
            rowTrailingConstraint,
            rowLayoutGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowLayoutGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: rowLayoutGuide.leadingAnchor, constant: inset),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AgentThreadRowMetrics.avatarTop),
            avatarView.widthAnchor.constraint(equalToConstant: AgentThreadRowMetrics.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: AgentThreadRowMetrics.avatarSize),

            pinView.leadingAnchor.constraint(equalTo: rowLayoutGuide.leadingAnchor, constant: AgentThreadRowMetrics.textLeading),
            pinView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: AgentThreadRowMetrics.pinVerticalOffset),
            pinView.widthAnchor.constraint(equalToConstant: AgentThreadRowMetrics.pinWidth),
            pinView.heightAnchor.constraint(equalToConstant: AgentThreadRowMetrics.titleLineHeight),

            titleLeadingConstraint,
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AgentThreadRowMetrics.titleTop),
            titleLabel.heightAnchor.constraint(equalToConstant: AgentThreadRowMetrics.titleLineHeight),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -AgentThreadRowMetrics.timeSpacing),

            timeLabel.trailingAnchor.constraint(equalTo: rowLayoutGuide.trailingAnchor, constant: -inset),
            timeLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            previewLabel.leadingAnchor.constraint(equalTo: rowLayoutGuide.leadingAnchor, constant: AgentThreadRowMetrics.textLeading),
            previewTrailingConstraint,
            previewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AgentThreadRowMetrics.previewTop),
            previewLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -AgentThreadRowMetrics.previewBottomInset
            ),

            previewImageView.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            previewImageView.centerYAnchor.constraint(
                equalTo: previewLabel.topAnchor,
                constant: AgentThreadRowMetrics.previewLineHeight / 2
            ),
            previewImageView.widthAnchor.constraint(equalToConstant: AgentThreadRowMetrics.previewImageSize),
            previewImageView.heightAnchor.constraint(equalToConstant: AgentThreadRowMetrics.previewImageSize),
            supportLabelLeadingConstraint,
            supportLabelView.centerYAnchor.constraint(
                equalTo: previewLabel.topAnchor,
                constant: AgentThreadRowMetrics.previewLineHeight / 2
            ),

            unreadBadge.trailingAnchor.constraint(equalTo: rowLayoutGuide.trailingAnchor, constant: -inset),
            unreadBadge.centerYAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: AgentThreadRowMetrics.previewTop + AgentThreadRowMetrics.unreadDotTopOffset
                    + AgentThreadRowMetrics.unreadDotSize / 2
            ),
        ])
    }
}

final class AgentThreadCell: AgentThreadRowCell, UIGestureRecognizerDelegate {
    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?
    var renameAction: (() -> Void)?
    var pinAction: (() -> Void)?
    var deleteAction: (() -> Void)?
    var onSwipeBegan: (() -> Void)?

    // The menu mirrors `contentView` over the blurred list, so the card it lifts the row into lives there too
    private lazy var contextMenuInteraction = ContextMenuInteraction(
        triggers: .longPress,
        sourcePortal: ContextMenuSourcePortal(),
        pressAnimation: .default(transformMode: .sublayerTransform),
        onWillPresent: { [weak self] in self?.setMenuCardVisible(true, animated: true) },
        onWillDismiss: { [weak self] in self?.setMenuCardVisible(false, animated: true) }
    ) { [weak self] _ in
        guard let self, self.motion.state == .closed else { return nil }
        return self.contextMenuConfigurationProvider?()
    }
    private let menuCardView = UIView()
    private var isShowingMenuCard = false
    /// Clips the actions to the strip the row has uncovered
    private let actionsClipView = UIView()
    private let actionButtons: [AgentThreadSwipeButton] = [
        AgentThreadSwipeButton(systemName: "pencil", color: UIColor(hex: "#0088FF")),
        AgentThreadSwipeButton(systemName: "pin.fill", color: UIColor(hex: "#FFCA00")),
        AgentThreadSwipeButton(systemName: "trash.fill", color: UIColor(hex: "#FF002E")),
    ]
    private lazy var swipeGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        return gesture
    }()
    private var motion = AgentThreadSwipeMotion()
    private lazy var swipeClock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.advanceSwipeAnimation() }
    private var previousSwipeAnimationTime: CFTimeInterval = 0
    /// While the Agent answers, its current step takes the preview's place, like Telegram's typing status. The view
    /// joins the row only then, so its gradient and spinning top animate only on rows that show them.
    let activityView = UIView()
    let activityIndicatorView = AgentThreadActivityTopView()
    let activityLabel = AgentGradientLabel()
    private var activityViewConstraints: [NSLayoutConstraint] = []
    private(set) var activityText: String?
    private var isPinnedThread = false
    private var isUnreadThread = false
    private var configuredThreadId: String?

    /// Open, or opening under the finger or a spring
    var isShowingSwipeActions: Bool { motion.isOpenOrOpening }

    /// Swipe distances are logical: they uncover the actions at the trailing edge, which is on the left in RTL
    private var swipeDirection: CGFloat { effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1 }

    private var swipeParameters: AgentThreadSwipeParameters {
        AgentThreadSwipeParameters(
            width: Double(bounds.width),
            buttonWidth: Double(AgentThreadSwipeMetrics.buttonSize),
            spacing: Double(AgentThreadSwipeMetrics.buttonSpacing),
            edgeInset: Double(AgentThreadSwipeMetrics.edgeInset),
            count: actionButtons.count,
            displayScale: Double(max(1, traitCollection.displayScale))
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "agent_thread_row"
        clipsToBounds = false
        contentView.layer.cornerCurve = .continuous

        menuCardView.translatesAutoresizingMaskIntoConstraints = false
        menuCardView.backgroundColor = .air.background
        menuCardView.layer.cornerRadius = AgentThreadMenuMetrics.cardCornerRadius
        menuCardView.layer.cornerCurve = .continuous
        menuCardView.isUserInteractionEnabled = false
        menuCardView.alpha = 0
        contentView.insertSubview(menuCardView, at: 0)
        NSLayoutConstraint.activate([
            menuCardView.leadingAnchor.constraint(equalTo: rowLayoutGuide.leadingAnchor),
            menuCardView.trailingAnchor.constraint(equalTo: rowLayoutGuide.trailingAnchor),
            menuCardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            menuCardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        actionsClipView.clipsToBounds = true
        insertSubview(actionsClipView, belowSubview: contentView)
        for (index, button) in actionButtons.enumerated() {
            button.addAction(UIAction { [weak self] _ in self?.performSwipeAction(at: index) }, for: .touchUpInside)
            actionsClipView.addSubview(button)
        }
        actionButtons[0].accessibilityLabel = lang("Rename")
        actionButtons[1].accessibilityLabel = lang("Pin")
        actionButtons[2].accessibilityLabel = lang("Delete")
        configureActivityViews()
        contextMenuInteraction.attach(to: contentView)
        addGestureRecognizer(swipeGesture)
        motion.configure(swipeParameters)
        renderSwipe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contextMenuConfigurationProvider = nil
        renameAction = nil
        pinAction = nil
        deleteAction = nil
        onSwipeBegan = nil
        resetSwipe()
        setMenuCardVisible(false, animated: false)
        setActivity(nil, animated: false)
        isUnreadThread = false
        updateUnreadDot()
        configuredThreadId = nil
    }

    override func layoutSubviews() {
        // The list cell lays `contentView` out by its frame, which the swipe's translation would distort
        contentView.transform = .identity
        super.layoutSubviews()
        let parameters = swipeParameters
        if parameters.width != motion.parameters.width || parameters.displayScale != motion.parameters.displayScale {
            if motion.state != .closed {
                resetSwipe()
            }
            motion.configure(parameters)
        }
        renderSwipe()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            resetSwipe()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        renderSwipe()
    }

    func closeSwipeActions(animated: Bool) {
        guard motion.isOpenOrOpening || (!animated && motion.state != .closed) else { return }
        motion.settle(to: 0, velocity: motion.body.velocity, animated: animated && !UIAccessibility.isReduceMotionEnabled)
        cancelSwipeGesture()
        renderSwipe()
        startSwipeAnimationIfNeeded()
    }

    private func performSwipeAction(at index: Int) {
        closeSwipeActions(animated: true)
        switch index {
        case 0: renameAction?()
        case 1: pinAction?()
        default: deleteAction?()
        }
    }

    // MARK: - Activity

    private func configureActivityViews() {
        activityView.translatesAutoresizingMaskIntoConstraints = false
        activityView.isUserInteractionEnabled = false
        activityView.alpha = 0
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityLabel.translatesAutoresizingMaskIntoConstraints = false
        activityLabel.numberOfLines = 1
        activityLabel.isAccessibilityElement = false
        // The label hugs its text, so the gradient spans the text as in the chat's status row
        activityLabel.setContentHuggingPriority(.required, for: .horizontal)
        activityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        activityView.addSubview(activityIndicatorView)
        activityView.addSubview(activityLabel)
        let size = AgentThreadActivityTopView.size
        NSLayoutConstraint.activate([
            activityIndicatorView.leadingAnchor.constraint(equalTo: activityView.leadingAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: activityLabel.centerYAnchor),
            activityIndicatorView.widthAnchor.constraint(equalToConstant: size.width),
            activityIndicatorView.heightAnchor.constraint(equalToConstant: size.height),

            activityLabel.leadingAnchor.constraint(equalTo: activityView.leadingAnchor, constant: size.width),
            activityLabel.trailingAnchor.constraint(lessThanOrEqualTo: activityView.trailingAnchor),
            activityLabel.topAnchor.constraint(equalTo: activityView.topAnchor),
            activityLabel.bottomAnchor.constraint(equalTo: activityView.bottomAnchor),
        ])
    }

    private func installActivityView() {
        guard activityView.superview !== contentView else { return }
        contentView.addSubview(activityView)
        activityViewConstraints = [
            activityView.leadingAnchor.constraint(
                equalTo: rowLayoutGuide.leadingAnchor,
                constant: AgentThreadRowMetrics.textLeading + AgentThreadRowMetrics.activityIndicatorLeading
            ),
            activityView.trailingAnchor.constraint(
                equalTo: rowLayoutGuide.trailingAnchor,
                constant: -AgentThreadRowMetrics.horizontalInset
            ),
            activityView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AgentThreadRowMetrics.previewTop),
            activityView.heightAnchor.constraint(equalToConstant: AgentThreadRowMetrics.previewLineHeight),
        ]
        NSLayoutConstraint.activate(activityViewConstraints)
        UIView.performWithoutAnimation { contentView.layoutIfNeeded() }
    }

    private func removeActivityView() {
        activityIndicatorView.setAnimating(false)
        NSLayoutConstraint.deactivate(activityViewConstraints)
        activityViewConstraints = []
        activityView.removeFromSuperview()
    }

    /// Shows what the Agent is doing in place of the preview, or the preview again with `nil`. As in Telegram, the two
    /// cross-fade.
    func setActivity(_ text: String?, animated: Bool) {
        let text = text?.nilIfEmpty
        guard text != activityText else { return }
        let isActiveBefore = activityText != nil
        activityText = text
        let isActive = text != nil
        let isAnimated = animated && window != nil && !UIAccessibility.isReduceMotionEnabled
        if let text {
            installActivityView()
            let applyText = {
                self.activityLabel.attributedText = NSAttributedString(string: text, attributes: AgentThreadRowMetrics.activityAttributes)
            }
            activityLabel.changeText(animated: isAnimated && isActiveBefore, apply: applyText)
        }
        if isActive {
            activityIndicatorView.setAnimating(true)
        }
        updateUnreadDot()
        updateAccessibilityLabel()
        guard isActiveBefore != isActive else { return }
        let apply = {
            self.previewLabel.alpha = isActive ? 0 : 1
            self.activityView.alpha = isActive ? 1 : 0
        }
        guard isAnimated else {
            apply()
            if !isActive { removeActivityView() }
            return
        }
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: apply
        ) { [weak self] _ in
            guard let self, self.activityText == nil else { return }
            self.removeActivityView()
        }
    }

    /// The dot marks an unseen answer once the Agent has finished; while it answers, the status takes the row
    private func updateUnreadDot() {
        unreadMark = isUnreadThread && activityText == nil ? .dot : nil
    }

    private func updateAccessibilityLabel() {
        let preview = activityText ?? previewLabel.text
        let unread = unreadMark != nil ? lang("Unread") : nil
        let supportLabel = supportLabelStyle == nil ? nil : supportLabelView.text
        accessibilityLabel = [titleLabel.text, supportLabel, preview, timeLabel.text, isPinnedThread ? lang("Pinned") : nil, unread]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: ", ")
    }

    // MARK: - Menu

    /// As in Telegram, the row's card grows in from the row on a spring and settles back quickly as the menu fades
    func setMenuCardVisible(_ isVisible: Bool, animated: Bool) {
        guard isShowingMenuCard != isVisible else { return }
        isShowingMenuCard = isVisible
        contentView.layoutIfNeeded()
        guard animated, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            applyMenuCard(isVisible: isVisible)
            return
        }
        if isVisible {
            UIView.animate(
                withDuration: 0.42,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyMenuCard(isVisible: true)
            }
        } else {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
            ) {
                self.applyMenuCard(isVisible: false)
            }
        }
    }

    private func applyMenuCard(isVisible: Bool) {
        rowContentInset = isVisible ? AgentThreadMenuMetrics.cardInset : 0
        menuCardView.alpha = isVisible ? 1 : 0
        liftProgress = isVisible ? 1 : 0
        contentView.layoutIfNeeded()
    }

    // MARK: - Swipe

    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        let translation = -gesture.translation(in: self).x * swipeDirection
        let velocity = -gesture.velocity(in: self).x * swipeDirection
        let isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        switch gesture.state {
        case .began:
            advanceSwipeAnimation()
            motion.begin()
            Haptics.prepare(.selection)
            // A swipe isn't a tap: the row lets its highlight go
            isHighlighted = false
            cancelHighlight()
            onSwipeBegan?()
            fallthrough
        case .changed:
            let isArmedBefore = motion.isArmed
            let x = gesture.location(in: self).x
            let distanceFromCommitEdge = swipeDirection < 0 ? bounds.width - x : x
            motion.change(
                translation: Double(translation),
                velocity: Double(velocity),
                distanceFromCommitEdge: Double(distanceFromCommitEdge),
                isReduceMotionEnabled: isReduceMotionEnabled
            )
            if isArmedBefore != motion.isArmed {
                Haptics.play(.selection)
            }
            renderSwipe()
            startSwipeAnimationIfNeeded()
        case .ended, .cancelled, .failed:
            guard motion.state == .dragging else { return }
            let isCommitted = motion.end(
                translation: Double(translation),
                velocity: Double(velocity),
                isCancelled: gesture.state != .ended,
                animated: !isReduceMotionEnabled
            )
            if isCommitted {
                // A full swipe runs Delete, which asks for confirmation, while the row slides back
                motion.settle(to: 0, velocity: motion.body.velocity, animated: !isReduceMotionEnabled)
                deleteAction?()
            }
            renderSwipe()
            startSwipeAnimationIfNeeded()
        default:
            break
        }
    }

    private func renderSwipe() {
        UIView.performWithoutAnimation {
            let distance = CGFloat(motion.body.value)
            let isRightToLeft = swipeDirection < 0
            contentView.transform = CGAffineTransform(translationX: -distance * swipeDirection, y: 0)
            let surface = min(1, max(0, CGFloat(motion.surface.value)))
            let surfaceOpacity = min(1, max(0, CGFloat(motion.surfaceOpacity.value)))
            let cardColor = AgentThreadSwipeMetrics.cardColor.resolvedColor(with: traitCollection)
            contentView.backgroundColor = surfaceOpacity > 0
                ? cardColor.withAlphaComponent(cardColor.cgColor.alpha * surfaceOpacity)
                : nil
            contentView.layer.cornerRadius = min(AgentThreadSwipeMetrics.cardCornerRadius, bounds.height / 2) * surface
            contentView.layer.maskedCorners = isRightToLeft
                ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
                : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            if !isShowingMenuCard {
                liftProgress = surfaceOpacity
            }
            layoutSwipeButtons(revealedWidth: max(0, distance), isRightToLeft: isRightToLeft)
        }
    }

    /// Lays the actions out from Telegram's reveal geometry: each pops in as the row uncovers its slot, and past the open
    /// distance the outermost one stretches over the uncovered strip while the others ride along with the row and fade
    private func layoutSwipeButtons(revealedWidth: CGFloat, isRightToLeft: Bool) {
        let width = bounds.width
        actionsClipView.frame = CGRect(
            x: isRightToLeft ? 0 : width - revealedWidth,
            y: 0,
            width: revealedWidth,
            height: bounds.height
        )
        let size = AgentThreadSwipeMetrics.buttonSize
        let geometry = motion.buttonGeometry
        // Geometry counts from the outer edge: Delete, then Pin, then Rename
        for (order, button) in actionButtons.reversed().enumerated() where order < geometry.count {
            let item = geometry[order]
            let buttonWidth = max(size, CGFloat(item.width))
            let centerX = isRightToLeft ? CGFloat(item.center) : width - CGFloat(item.center)
            let scale = max(0.0001, CGFloat(motion.scales[order].value))
            let opacity = min(1, max(0, CGFloat(motion.opacities[order].value)))
            button.transform = .identity
            button.bounds = CGRect(x: 0, y: 0, width: buttonWidth, height: size)
            button.center = CGPoint(x: centerX - actionsClipView.frame.minX, y: bounds.midY)
            button.transform = CGAffineTransform(scaleX: scale, y: scale)
            button.alpha = opacity
            button.isUserInteractionEnabled = opacity > 0.1 && scale > 0.3
            if order == 0 {
                // Once armed, the icon moves to the end of the stretched action that follows the finger
                let travel = (buttonWidth - size) / 2 * min(1, max(0, CGFloat(motion.expansion.value)))
                button.iconOffset = isRightToLeft ? travel : -travel
            }
        }
    }

    private func startSwipeAnimationIfNeeded() {
        guard !motion.isAtRest else {
            stopSwipeAnimation()
            return
        }
        guard !swipeClock.isRunning else { return }
        previousSwipeAnimationTime = CACurrentMediaTime()
        swipeClock.start()
    }

    private func advanceSwipeAnimation() {
        guard swipeClock.isRunning else { return }
        let now = CACurrentMediaTime()
        motion.advance(by: now - previousSwipeAnimationTime)
        previousSwipeAnimationTime = now
        renderSwipe()
        startSwipeAnimationIfNeeded()
    }

    private func stopSwipeAnimation() {
        swipeClock.stop()
    }

    private func resetSwipe() {
        stopSwipeAnimation()
        cancelSwipeGesture()
        motion.reset()
        renderSwipe()
    }

    private func cancelSwipeGesture() {
        guard swipeGesture.state == .began || swipeGesture.state == .changed else { return }
        swipeGesture.isEnabled = false
        swipeGesture.isEnabled = true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard !isShowingMenuCard else { return false }
        let velocity = swipeGesture.velocity(in: self)
        guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
        let location = swipeGesture.location(in: self)
        let translation = swipeGesture.translation(in: self)
        let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        // A touch on an action stays a tap on it
        if actionButtons.contains(where: { $0.isUserInteractionEnabled && $0.point(inside: $0.convert(start, from: self), with: nil) }) {
            return false
        }
        if motion.state != .closed && (abs(motion.body.value) >= 0.1 || abs(motion.body.velocity) >= 5) {
            return true
        }
        guard velocity.x * swipeDirection < 0 else { return false }
        let edgeZone = AgentThreadSwipeMetrics.getEdgeZoneWidth(for: window?.bounds.width ?? bounds.width)
        // Only a swipe that starts near the trailing edge opens the actions, so tab paging keeps the rest of the row
        return swipeDirection < 0 ? start.x <= bounds.minX + edgeZone : start.x >= bounds.maxX - edgeZone
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Tab paging waits until the row declines the swipe
        guard gestureRecognizer === swipeGesture,
              otherGestureRecognizer is UIPanGestureRecognizer,
              let scrollView = otherGestureRecognizer.view as? UIScrollView,
              isDescendant(of: scrollView) else { return false }
        return scrollView.contentSize.width > scrollView.bounds.width + 1
    }

    /// `activity` is what the Agent is doing while it answers in the thread, shown in place of the preview; `isUnread`
    /// marks an answer the user hasn't seen
    func configure(with item: ApiAgentV2ThreadListItem, activity: String? = nil, isUnread: Bool = false, now: Date = .now) {
        let thread = item.thread
        avatarView.configure(seed: thread.id, emoji: thread.icon)
        let title = thread.title?.nilIfEmpty
        let preview = item.preview?.nilIfEmpty
        let isPinned = thread.isPinned == true
        let time = AgentThreadDateFormatting.formatRowTimestamp(
            for: thread.lastActivityAt,
            shouldShowDateWhenNotToday: isPinned,
            relativeTo: now
        )
        // A chat with support carries its label on the preview's line, which shows for it without a preview too
        supportLabelStyle = AgentSupportPresentation.getLabelStyle(for: thread.support)
        let shownPreview = title == nil ? nil : preview
        setTexts(
            title: title ?? preview ?? lang("New Chat"),
            preview: shownPreview ?? (supportLabelStyle == nil ? nil : ""),
            time: time
        )
        // A row shows the picture of its latest message, as Telegram's chat list does. Only a news post has one, and it
        // is a discussion's latest message while it is the thread's only one.
        let isNewsPostLatest = thread.messageCount <= 1
        setPreviewImage(url: title == nil || !isNewsPostLatest ? nil : thread.news?.imageUrl.flatMap(URL.init(string:)))
        isPinIconVisible = isPinned
        isPinnedThread = isPinned
        actionButtons[1].setSystemName(isPinned ? "pin.slash.fill" : "pin.fill")
        actionButtons[1].accessibilityLabel = lang(isPinned ? "Unpin" : "Pin")
        // A row that keeps its thread animates the change; a reused one shows its thread's state at once
        isUnreadThread = isUnread
        setActivity(activity, animated: configuredThreadId == thread.id)
        updateUnreadDot()
        configuredThreadId = thread.id
        updateAccessibilityLabel()
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: lang(isPinned ? "Unpin" : "Pin")) { [weak self] _ in
                self?.pinAction?()
                return true
            },
            UIAccessibilityCustomAction(name: lang("Rename")) { [weak self] _ in
                self?.renameAction?()
                return true
            },
            UIAccessibilityCustomAction(name: lang("Delete")) { [weak self] _ in
                self?.deleteAction?()
                return true
            }
        ]
    }
}

/// A round action revealed by swiping a thread row. The outermost one stretches into a pill on a long swipe.
final class AgentThreadSwipeButton: UIButton {
    private let color: UIColor
    private let highlightedColor: UIColor
    private let iconView = UIImageView()
    private var systemName: String

    /// The icon's horizontal offset from the button's center
    var iconOffset: CGFloat = 0 {
        didSet {
            guard iconOffset != oldValue else { return }
            setNeedsLayout()
        }
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? highlightedColor : color }
    }

    init(systemName: String, color: UIColor) {
        self.systemName = systemName
        self.color = color
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        highlightedColor = color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            ? UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.9, alpha: alpha)
            : color
        super.init(frame: .zero)
        backgroundColor = color
        layer.cornerRadius = AgentThreadSwipeMetrics.buttonSize / 2
        layer.cornerCurve = .circular
        iconView.tintColor = .white
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        setSystemName(systemName, force: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.bounds = CGRect(origin: .zero, size: iconView.image?.size ?? .zero)
        iconView.center = CGPoint(x: bounds.midX + iconOffset, y: bounds.midY)
    }

    func setSystemName(_ name: String, force: Bool = false) {
        guard force || name != systemName else { return }
        systemName = name
        iconView.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        setNeedsLayout()
    }
}

/// The Agent's spinning top before a row's status while the Agent answers there, as the chat shows the Agent at work.
/// Its renderer joins the row only while it spins.
final class AgentThreadActivityTopView: UIView {
    /// The box the status leaves for the top, 3 pt before the preview's start
    static let size = CGSize(width: 24, height: 20)
    private static let side: CGFloat = 20

    private var topView: AgentSpinningTopView?

    var isAnimating: Bool { topView != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { Self.size }

    func setAnimating(_ isAnimating: Bool) {
        guard isAnimating != self.isAnimating else { return }
        if isAnimating {
            let topView = AgentSpinningTopView()
            topView.isUserInteractionEnabled = false
            topView.isAccessibilityElement = false
            addSubview(topView)
            self.topView = topView
            setNeedsLayout()
        } else {
            topView?.removeFromSuperview()
            topView = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topView?.frame = CGRect(
            x: (bounds.width - Self.side) / 2,
            y: (bounds.height - Self.side) / 2,
            width: Self.side,
            height: Self.side
        )
    }
}
