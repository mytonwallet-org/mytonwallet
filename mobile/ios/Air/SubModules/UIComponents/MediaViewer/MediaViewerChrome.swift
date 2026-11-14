import ContextMenuKit
import UIKit
import WalletContext

extension MediaViewer {
    /// What Telegram's gallery shows around a picture: its date on the capsule over it, and its caption and the actions
    /// on it under it
    public struct Details {
        public let date: String?
        public let caption: NSAttributedString?
        public let actions: [Action]
        /// The button at the header's trailing end, which opens a menu
        public let menu: Menu?
        /// A tap on a link in the caption
        public let onLinkTap: ((URL) -> Void)?

        public init(
            date: String?,
            caption: NSAttributedString?,
            actions: [Action],
            menu: Menu? = nil,
            onLinkTap: ((URL) -> Void)? = nil
        ) {
            self.date = date
            self.caption = caption
            self.actions = actions
            self.menu = menu
            self.onLinkTap = onLinkTap
        }
    }

    /// A header button that opens a menu under it, as the back button stands at the other end
    public struct Menu {
        public let title: String
        public let image: UIImage?
        public let makeConfiguration: () -> ContextMenuConfiguration?

        public init(title: String, image: UIImage?, makeConfiguration: @escaping () -> ContextMenuConfiguration?) {
            self.title = title
            self.image = image
            self.makeConfiguration = makeConfiguration
        }
    }

    /// A button of the footer, as an item of Telegram's gallery footer
    public struct Action {
        /// Telegram's footer keeps its forward button at the leading end and the rest at the trailing end
        public enum Placement {
            case leading
            case trailing
        }

        /// The size and weight of a footer button's symbol, as large and as thin as Telegram's footer icons draw theirs:
        /// its 30 pt template images draw glyphs of about 22 pt with 1.33 pt strokes, as 18 pt regular symbols do at the
        /// medium scale, which a plain button would otherwise make large
        public static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular, scale: .medium)

        public let title: String
        public let image: UIImage?
        public let placement: Placement
        /// Runs the action, with the button to present from
        public let handler: (UIView) -> Void

        public init(title: String, image: UIImage?, placement: Placement, handler: @escaping (UIView) -> Void) {
            self.title = title
            self.image = image
            self.placement = placement
            self.handler = handler
        }
    }
}

/// The heights of Telegram's gallery footer (`ChatItemGalleryFooterContentNode`): a caption over a row of 44 pt glass
/// buttons. A caption taller than 100 pt shows 80 pt of itself and scrolls; pulled up, it rises with the panel until
/// 238 pt of the screen stay above it, and scrolls on from there.
struct MediaViewerFooterLayout: Equatable {
    static let buttonHeight: CGFloat = 44
    static let basePanelHeight: CGFloat = 54
    static let captionTopInset: CGFloat = 8
    static let captionBottomInset: CGFloat = 8 + 14
    static let captionSideInset: CGFloat = 16
    static let maxUnclampedTextHeight: CGFloat = 100
    static let clampedTextHeight: CGFloat = 80
    static let expandedTopReserve: CGFloat = 238

    /// The footer's height, from the caption's top to the screen's bottom
    let panelHeight: CGFloat
    /// How much of the caption shows at rest
    let visibleTextHeight: CGFloat
    /// The caption's resting height with its insets, the height of its scroll view
    let captionPanelHeight: CGFloat
    let isScrollable: Bool
    /// How far the panel has risen above its resting height as the caption is pulled up
    let textOffset: CGFloat
    /// The caption's offset when a tap has pulled it up as far as the panel rises
    let expandedOffsetY: CGFloat

    /// `pixel` is the screen's pixel in points, which Telegram's panel stops short of the 238 pt by
    init(textHeight: CGFloat?, contentOffsetY: CGFloat, viewHeight: CGFloat, bottomInset: CGFloat, pixel: CGFloat = 0) {
        let basePanelHeight = Self.basePanelHeight + bottomInset
        guard let textHeight, textHeight > 0 else {
            panelHeight = basePanelHeight
            visibleTextHeight = 0
            captionPanelHeight = 0
            isScrollable = false
            textOffset = 0
            expandedOffsetY = 0
            return
        }
        isScrollable = textHeight > Self.maxUnclampedTextHeight
        visibleTextHeight = isScrollable ? Self.clampedTextHeight : textHeight
        captionPanelHeight = visibleTextHeight + Self.captionTopInset + Self.captionBottomInset
        let maxTextOffset = max(0, viewHeight - bottomInset - Self.expandedTopReserve - pixel)
        textOffset = min(maxTextOffset, contentOffsetY)
        panelHeight = max(0, basePanelHeight + captionPanelHeight + textOffset)
        expandedOffsetY = isScrollable ? min(maxTextOffset, textHeight - visibleTextHeight) : 0
    }

    /// Whether the caption is pulled up past half of how far a tap pulls it
    func isExpanded(atOffsetY offsetY: CGFloat) -> Bool {
        expandedOffsetY > 0 && offsetY > expandedOffsetY / 2
    }
}

/// A view that lets touches through everywhere but on its subviews
@MainActor
class MediaViewerPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

/// Black over the edge of the screen behind a bar, fading toward the picture over its last 120 pt on the curve of
/// Telegram's edge effect, as Telegram's gallery shades its bars
@MainActor
final class MediaViewerShadeView: UIView {
    static let fadeHeight: CGFloat = 120
    /// How much of the shade shows across its fade, from the screen's side (0) to the picture's (1): Telegram's edge
    /// effect holds most of it through the first fifth and lets it go in an S toward the picture
    static let fadeCurve: [(location: CGFloat, alpha: CGFloat)] = [
        (0, 1), (0.1, 0.983), (0.2, 0.941), (0.3, 0.847), (0.4, 0.689), (0.5, 0.483),
        (0.6, 0.286), (0.7, 0.136), (0.8, 0.053), (0.9, 0.027), (1, 0),
    ]

    private let isTop: Bool
    private let gradientLayer = CAGradientLayer()

    init(isTop: Bool, opacity: CGFloat) {
        self.isTop = isTop
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(gradientLayer)
        let colors = Self.fadeCurve.map { UIColor.black.withAlphaComponent(opacity * $0.alpha).cgColor }
        gradientLayer.colors = isTop ? colors : Array(colors.reversed())
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(1, bounds.height)
        let fade = min(Self.fadeHeight, height) / height
        // The shade is solid from the screen's edge to where the fade starts
        let locations = isTop
            ? Self.fadeCurve.map { 1 - fade + $0.location * fade }
            : Self.fadeCurve.reversed().map { (1 - $0.location) * fade }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        gradientLayer.locations = locations.map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }
}

/// Icon buttons on one capsule of glass, as Telegram's gallery groups its bar and footer buttons
/// (`GlassControlGroupComponent`): each button is a 44 pt square with its glyph in the middle, and the capsule is as
/// wide as its buttons, with no padding of its own
@MainActor
final class MediaViewerButtonGroup: UIView {
    static let itemSize = WGlassButtonMetrics.size

    let glassView = WGlassView(cornerRadius: nil)
    private(set) var buttons: [UIButton] = []
    private var handlers: [(UIView) -> Void] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    struct Item {
        let title: String
        let image: UIImage?
        /// The size and weight the button draws its symbol at, in its middle; nil draws it as a plain button does, as
        /// the Agent header's buttons draw theirs
        let symbolConfiguration: UIImage.SymbolConfiguration?
        let identifier: String?
        let handler: (UIView) -> Void
    }

    var preferredSize: CGSize {
        CGSize(width: Self.itemSize * CGFloat(buttons.count), height: Self.itemSize)
    }

    func setItems(_ items: [Item]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = items.map { item in
            let button: UIButton
            if let symbolConfiguration = item.symbolConfiguration {
                // A symbol of its own size stands in its button's middle, as Telegram's footer icons do. A plain
                // button would place it by its alignment rectangle, which puts some symbols beside the middle.
                button = UIButton(type: .system)
                button.setImage(item.image, for: .normal)
                button.setPreferredSymbolConfiguration(symbolConfiguration, forImageIn: .normal)
                button.tintColor = .white
            } else {
                // Built as the Agent header's buttons are, so a symbol that both draw comes out the same
                var configuration = UIButton.Configuration.plain()
                configuration.image = item.image
                configuration.baseForegroundColor = .white
                configuration.contentInsets = .zero
                button = UIButton(configuration: configuration)
            }
            button.accessibilityLabel = item.title
            button.accessibilityIdentifier = item.identifier
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button, let index = self.buttons.firstIndex(of: button) else { return }
                self.performAction(at: index)
            }, for: .touchUpInside)
            glassView.contentView.addSubview(button)
            return button
        }
        handlers = items.map { $0.handler }
        isHidden = buttons.isEmpty
        setNeedsLayout()
    }

    /// Runs the action of the button at `index`, as a tap on it does
    func performAction(at index: Int) {
        guard buttons.indices.contains(index), handlers.indices.contains(index) else { return }
        handlers[index](buttons[index])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.frame = bounds
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: Self.itemSize * CGFloat(index), y: 0, width: Self.itemSize, height: Self.itemSize)
        }
    }
}

/// Telegram's gallery header (`GalleryControllerNode` with `GalleryTitleView`): the back button in the bar's 44 pt row
/// under the status bar, a capsule in the middle with "N of M" over the picture's date, or the date alone for a single
/// picture, and a picture's menu button at the trailing end
@MainActor
final class MediaViewerHeaderView: MediaViewerPassthroughView {
    /// The bar's height under the status bar
    static let barHeight: CGFloat = 60
    static let sideInset: CGFloat = 16
    static let capsuleMinWidth: CGFloat = 150
    static let capsulePadding: CGFloat = 14
    static let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let subtitleFont = UIFont.systemFont(ofSize: 12)

    let backGroup = MediaViewerButtonGroup()
    let menuGroup = MediaViewerButtonGroup()
    /// What the menu button opens for the picture shown
    private(set) var makeMenuConfiguration: (() -> ContextMenuConfiguration?)?
    /// The menu grows out of its glass button, as the app's other glass buttons open theirs
    private lazy var menuInteraction = ContextMenuInteraction(triggers: [], presentationMode: .zoomPopover) { [weak self] _ in
        self?.makeMenuConfiguration?()
    }
    let titleGlass = WGlassView(cornerRadius: nil)
    /// The capsule's first line: "N of M", or the date of a single picture
    let titleLabel = MediaViewerAnimatedLabel()
    /// The date under "N of M"
    let subtitleLabel = MediaViewerAnimatedLabel()
    private(set) var isShown = true
    private var hasTitle = false

    init(onBack: @escaping () -> Void) {
        super.init(frame: .zero)
        // The Agent header's back chevron, drawn by a plain button as there
        let backImage = UIImage(systemName: "chevron.backward", withConfiguration: WGlassButtonMetrics.symbolConfiguration)?
            .imageFlippedForRightToLeftLayoutDirection()
        backGroup.setItems([.init(
            title: lang("Back"),
            image: backImage,
            symbolConfiguration: nil,
            identifier: "MediaViewerBack",
            handler: { _ in onBack() }
        )])
        addSubview(backGroup)
        menuGroup.isHidden = true
        addSubview(menuGroup)

        titleLabel.font = Self.titleFont
        titleLabel.textColor = .white
        subtitleLabel.font = Self.subtitleFont
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        titleGlass.contentView.addSubview(titleLabel)
        titleGlass.contentView.addSubview(subtitleLabel)
        titleGlass.isUserInteractionEnabled = false
        titleGlass.isAccessibilityElement = true
        titleGlass.accessibilityTraits = .header
        addSubview(titleGlass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `counter` over `date`, or `date` alone without a counter, changing only what differs from the page before
    /// when `animated`
    func configure(counter: String?, date: String?, direction: MediaViewerAnimatedLabel.Direction, animated: Bool) {
        let counter = counter?.nilIfEmpty
        titleLabel.setText(counter ?? date, direction: direction, animated: animated)
        subtitleLabel.setText(counter == nil ? nil : date, direction: direction, animated: animated)
        hasTitle = titleLabel.text != nil
        titleGlass.isHidden = !hasTitle
        titleGlass.accessibilityLabel = [counter, date].compactMap { $0?.nilIfEmpty }.joined(separator: ", ")
        setNeedsLayout()
    }

    /// Shows the menu button for `menu`, or hides it without one
    func configureMenu(_ menu: MediaViewer.Menu?) {
        makeMenuConfiguration = menu?.makeConfiguration
        menuGroup.isHidden = menu == nil
        guard let menu, menuGroup.buttons.first?.accessibilityLabel != menu.title else { return }
        menuGroup.setItems([.init(
            title: menu.title,
            image: menu.image,
            symbolConfiguration: nil,
            identifier: "MediaViewerMenu",
            handler: { [weak self] _ in self?.menuInteraction.present() }
        )])
        if let button = menuGroup.buttons.first {
            menuInteraction.attach(to: button)
        }
    }

    /// Lays the header out in `bounds` of the viewer, the bar's height under the status bar, with its row of buttons
    /// from `rowY`, the back button `leadingInset` from the safe area's leading edge, 16 pt by default, and the menu
    /// button 16 pt from its trailing edge
    func layout(safeArea: UIEdgeInsets, rowY: CGFloat, leadingInset: CGFloat?, isRightToLeft: Bool) {
        let size = MediaViewerButtonGroup.itemSize
        let inset = (isRightToLeft ? safeArea.right : safeArea.left) + (leadingInset ?? Self.sideInset)
        backGroup.frame = CGRect(
            x: isRightToLeft ? bounds.width - inset - size : inset,
            y: rowY,
            width: size,
            height: size
        )
        let trailingInset = (isRightToLeft ? safeArea.left : safeArea.right) + Self.sideInset
        menuGroup.frame = CGRect(
            x: isRightToLeft ? trailingInset : bounds.width - trailingInset - size,
            y: rowY,
            width: size,
            height: size
        )

        let maxWidth = max(0, bounds.width - safeArea.left - safeArea.right - (size + Self.sideInset + 8) * 2)
        let labelWidth = max(1, maxWidth - Self.capsulePadding * 2)
        let fittingSize = CGSize(width: labelWidth, height: .greatestFiniteMagnitude)
        let titleSize = titleLabel.sizeThatFits(fittingSize)
        let subtitleSize = subtitleLabel.sizeThatFits(fittingSize)
        let capsuleWidth = min(maxWidth, max(Self.capsuleMinWidth, max(titleSize.width, subtitleSize.width)) + Self.capsulePadding * 2)
        let centerX = safeArea.left + (bounds.width - safeArea.left - safeArea.right) / 2
        titleGlass.frame = CGRect(x: (centerX - capsuleWidth / 2).rounded(.down), y: rowY, width: capsuleWidth, height: size)
        let innerWidth = max(0, capsuleWidth - Self.capsulePadding * 2)
        let titleHeight = min(titleSize.height, size)
        let subtitleHeight = min(subtitleSize.height, size)
        let spacing: CGFloat = titleHeight > 0 && subtitleHeight > 0 ? 2 : 0
        let top = ((size - titleHeight - subtitleHeight - spacing) / 2).rounded(.down)
        titleLabel.frame = CGRect(x: Self.capsulePadding, y: top, width: innerWidth, height: titleHeight)
        subtitleLabel.frame = CGRect(x: Self.capsulePadding, y: top + titleHeight + spacing, width: innerWidth, height: subtitleHeight)
    }

    /// Shows or hides the header's glass; call it in an animation block to animate
    func setShown(_ isShown: Bool) {
        self.isShown = isShown
        backGroup.glassView.setMaterialized(isShown)
        menuGroup.glassView.setMaterialized(isShown)
        titleGlass.setMaterialized(isShown)
        accessibilityElementsHidden = !isShown
    }

    /// The header's controls, which take touches while the header shows
    func containsControl(at point: CGPoint) -> Bool {
        guard isShown else { return false }
        return backGroup.frame.contains(point)
            || (!menuGroup.isHidden && menuGroup.frame.contains(point))
            || (hasTitle && titleGlass.frame.contains(point))
    }
}

/// The caption's scroll view, which keeps its resting height as the panel rises and takes touches on the text the risen
/// panel shows below it as well
@MainActor
final class MediaViewerCaptionScrollView: UIScrollView {
    /// How far below its bounds the caption's text shows
    var touchExtension: CGFloat = 0

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var area = bounds
        area.size.height += touchExtension
        return area.contains(point)
    }
}

/// Telegram's gallery footer (`ChatItemGalleryFooterContentNode`): the caption, which a tap pulls up or lets back down
/// and which scrolls when it is long, over the buttons, with black shading the screen's bottom behind them
@MainActor
final class MediaViewerFooterView: UIView, UIScrollViewDelegate, UITextViewDelegate, UIGestureRecognizerDelegate {
    /// How far a hidden footer goes down, as Telegram's goes without a thumbnail strip
    static func getHiddenOffset(isLandscape: Bool) -> CGFloat {
        isLandscape ? 44 : 54
    }

    let shadeView = MediaViewerShadeView(isTop: false, opacity: 0.65)
    let captionClipView = UIView()
    let captionScrollView = MediaViewerCaptionScrollView()
    let captionTextView = UITextView()
    let leadingGroup = MediaViewerButtonGroup()
    let trailingGroup = MediaViewerButtonGroup()
    /// Asks the viewer to lay the footer out again as the caption's scroll changes its height
    var onCaptionScroll: (() -> Void)?
    private(set) var layout = MediaViewerFooterLayout(textHeight: nil, contentOffsetY: 0, viewHeight: 0, bottomInset: 0)
    private(set) var isShown = true
    private(set) var showsCaption = false
    private var details: MediaViewer.Details?
    private let captionMask = CAGradientLayer()
    private var textHeight: CGFloat?
    private var measuredWidth: CGFloat = 0
    private var contentAlpha: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(shadeView)

        captionClipView.clipsToBounds = true
        addSubview(captionClipView)
        captionScrollView.clipsToBounds = false
        captionScrollView.showsVerticalScrollIndicator = false
        captionScrollView.showsHorizontalScrollIndicator = false
        captionScrollView.scrollsToTop = false
        captionScrollView.contentInsetAdjustmentBehavior = .never
        captionScrollView.alwaysBounceVertical = false
        captionScrollView.delegate = self
        captionClipView.addSubview(captionScrollView)

        captionTextView.isEditable = false
        captionTextView.isSelectable = true
        captionTextView.isScrollEnabled = false
        captionTextView.backgroundColor = .clear
        captionTextView.textContainerInset = .zero
        captionTextView.textContainer.lineFragmentPadding = 0
        captionTextView.dataDetectorTypes = []
        captionTextView.linkTextAttributes = [.foregroundColor: UIColor(red: 0x5a / 255, green: 0xc8 / 255, blue: 0xfa / 255, alpha: 1)]
        captionTextView.textDragInteraction?.isEnabled = false
        captionTextView.delegate = self
        captionTextView.accessibilityIdentifier = "MediaViewerCaption"
        captionScrollView.addSubview(captionTextView)

        let captionTap = UITapGestureRecognizer(target: self, action: #selector(handleCaptionTap(_:)))
        captionTap.delegate = self
        captionScrollView.addGestureRecognizer(captionTap)

        captionMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        addSubview(leadingGroup)
        addSubview(trailingGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with details: MediaViewer.Details?) {
        self.details = details
        captionTextView.attributedText = details?.caption ?? NSAttributedString()
        textHeight = nil
        captionScrollView.setContentOffset(.zero, animated: false)
        let actions = details?.actions ?? []
        func items(_ placement: MediaViewer.Action.Placement) -> [MediaViewerButtonGroup.Item] {
            actions.filter { $0.placement == placement }.map {
                .init(
                    title: $0.title,
                    image: $0.image,
                    symbolConfiguration: MediaViewer.Action.symbolConfiguration,
                    identifier: nil,
                    handler: $0.handler
                )
            }
        }
        leadingGroup.setItems(items(.leading))
        trailingGroup.setItems(items(.trailing))
    }

    var hasCaption: Bool {
        details?.caption.map { $0.length > 0 } ?? false
    }

    /// The footer's heights for a viewer of `size`; a caption shows unless the viewer is a compact landscape one, as in
    /// Telegram
    func measure(size: CGSize, safeArea: UIEdgeInsets, showsCaption: Bool) -> MediaViewerFooterLayout {
        self.showsCaption = showsCaption && hasCaption
        let textWidth = max(1, size.width - MediaViewerFooterLayout.captionSideInset * 2 - safeArea.left - safeArea.right)
        if textHeight == nil || abs(measuredWidth - textWidth) > 0.5 {
            measuredWidth = textWidth
            textHeight = hasCaption
                ? captionTextView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height.rounded(.up)
                : nil
        }
        layout = MediaViewerFooterLayout(
            textHeight: self.showsCaption ? textHeight : nil,
            contentOffsetY: captionScrollView.contentOffset.y,
            viewHeight: size.height,
            bottomInset: safeArea.bottom,
            pixel: 1 / max(1, traitCollection.displayScale)
        )
        return layout
    }

    /// Lays out the footer's own views for its `layout`, its frame being set
    func layoutContent(safeArea: UIEdgeInsets, isRightToLeft: Bool) {
        let width = bounds.width
        let panelHeight = layout.panelHeight
        let shadeOffset: CGFloat = 70
        shadeView.frame = CGRect(x: 0, y: -shadeOffset, width: width, height: panelHeight + shadeOffset)

        if showsCaption, let textHeight {
            let clipHeight = max(0, layout.captionPanelHeight + layout.textOffset + MediaViewerFooterLayout.basePanelHeight + safeArea.bottom - 14)
            captionClipView.frame = CGRect(x: 0, y: 0, width: width, height: clipHeight)
            captionScrollView.isScrollEnabled = layout.isScrollable
            let scrollFrame = CGRect(x: 0, y: 0, width: width, height: layout.captionPanelHeight)
            if captionScrollView.frame != scrollFrame {
                captionScrollView.frame = scrollFrame
            }
            captionScrollView.touchExtension = layout.textOffset
            let contentSize = CGSize(
                width: width,
                height: textHeight + MediaViewerFooterLayout.captionTopInset + MediaViewerFooterLayout.captionBottomInset
            )
            if captionScrollView.contentSize != contentSize {
                captionScrollView.contentSize = contentSize
            }
            captionTextView.frame = CGRect(
                x: MediaViewerFooterLayout.captionSideInset + safeArea.left,
                y: MediaViewerFooterLayout.captionTopInset + layout.textOffset,
                width: measuredWidth,
                height: textHeight
            )
            if layout.isScrollable {
                let fade = min(90, clipHeight) / max(1, clipHeight)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                captionMask.frame = captionClipView.bounds
                captionMask.locations = [0, NSNumber(value: Double(1 - fade)), 1]
                CATransaction.commit()
                captionClipView.layer.mask = captionMask
            } else {
                captionClipView.layer.mask = nil
            }
        }
        captionClipView.isHidden = !showsCaption
        captionClipView.alpha = contentAlpha
        shadeView.alpha = contentAlpha * (showsCaption ? 1 : 0.5)

        var insets = UIEdgeInsets(top: 0, left: 8 + safeArea.left, bottom: safeArea.bottom + 8, right: 8 + safeArea.right)
        if safeArea.bottom <= 32 {
            insets.left += 18
            insets.right += 18
        }
        let buttonsY = panelHeight - insets.bottom - MediaViewerFooterLayout.buttonHeight
        let leadingSize = leadingGroup.preferredSize
        let trailingSize = trailingGroup.preferredSize
        let leftX = insets.left
        leadingGroup.frame = CGRect(
            x: isRightToLeft ? width - insets.right - leadingSize.width : leftX,
            y: buttonsY,
            width: leadingSize.width,
            height: leadingSize.height
        )
        trailingGroup.frame = CGRect(
            x: isRightToLeft ? leftX : width - insets.right - trailingSize.width,
            y: buttonsY,
            width: trailingSize.width,
            height: trailingSize.height
        )
    }

    /// Shows or hides the footer's glass; call it in an animation block to animate
    func setShown(_ isShown: Bool) {
        self.isShown = isShown
        leadingGroup.glassView.setMaterialized(isShown)
        trailingGroup.glassView.setMaterialized(isShown)
        accessibilityElementsHidden = !isShown
        // A hidden footer still stands over the picture and lets its swipes through to the pager
        isUserInteractionEnabled = isShown
    }

    /// The caption's and the shade's opacity, which a swipe down fades as Telegram's gallery fades its footer
    func setContentAlpha(_ alpha: CGFloat) {
        contentAlpha = alpha
        captionClipView.alpha = alpha
        shadeView.alpha = alpha * (showsCaption ? 1 : 0.5)
    }

    /// Pulls a long caption up as far as the panel rises, or lets a pulled-up one back down
    func toggleCaptionExpansion(animated: Bool = !UIAccessibility.isReduceMotionEnabled) {
        guard layout.isScrollable else { return }
        let offsetY = layout.isExpanded(atOffsetY: captionScrollView.contentOffset.y) ? 0 : layout.expandedOffsetY
        captionScrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: animated)
    }

    var isCaptionExpanded: Bool {
        layout.isExpanded(atOffsetY: captionScrollView.contentOffset.y)
    }

    @objc private func handleCaptionTap(_ gesture: UITapGestureRecognizer) {
        toggleCaptionExpansion()
    }

    /// A tap on a link keeps the link's own action
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        getLink(at: touch.location(in: captionTextView)) == nil
    }

    private func getLink(at point: CGPoint) -> URL? {
        guard captionTextView.bounds.contains(point), captionTextView.attributedText.length > 0 else { return nil }
        let layoutManager = captionTextView.layoutManager
        let index = layoutManager.characterIndex(
            for: point,
            in: captionTextView.textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index < captionTextView.attributedText.length else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil),
            in: captionTextView.textContainer
        )
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        let link = captionTextView.attributedText.attribute(.link, at: index, effectiveRange: nil)
        return link as? URL ?? (link as? String).flatMap(URL.init(string:))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === captionScrollView else { return }
        onCaptionScroll?()
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if interaction == .invokeDefaultAction {
            details?.onLinkTap?(url)
        }
        return false
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange) -> Bool {
        details?.onLinkTap?(url)
        return false
    }
}
