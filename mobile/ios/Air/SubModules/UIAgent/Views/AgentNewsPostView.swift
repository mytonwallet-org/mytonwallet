import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// A news post as the Agent shows it, in the News feed and at the top of the news' discussion alike: the Agent's
/// tailed bubble with the picture, the headline, the body, the line of its sources and the time in its trailing
/// corner. The discussion heads it with "News"; the feed ends it with its Discuss strip, and the discussion hangs its
/// follow-ups under it.
final class AgentNewsPostView: UIView {
    struct Content: Equatable {
        let accessibilityIdentifier: String
        /// The line above the post in its discussion
        let header: String
        let headline: String
        let body: String?
        let imageURL: URL?
        let sourceURL: String?
        let sourceLine: AgentNewsSourceLine?
        let time: String

        /// The post at the top of a news discussion, dated unless it is today's
        init(news: ApiAgentV2ThreadNewsCard) {
            accessibilityIdentifier = "AgentNewsPost-\(news.eventId)"
            header = lang("News")
            headline = news.headline
            body = news.body?.nilIfEmpty ?? news.excerpt?.nilIfEmpty
            imageURL = news.imageUrl.flatMap(URL.init(string:))
            sourceURL = news.sources?.first?.url
            sourceLine = AgentNewsSourceLine(sources: news.sources ?? [], legacySource: news.source)
            time = AgentNewsMetaView.formatDiscussionTime(for: news.publishedAt)
        }

        /// A news item of the feed, where the day line above it gives its date
        init(item: ApiAgentV2NewsFeedItem, time: String) {
            accessibilityIdentifier = "AgentNewsPost-\(item.eventId)"
            header = lang("News")
            headline = item.headline
            body = item.body.nilIfEmpty
            imageURL = item.imageUrl.flatMap(URL.init(string:))
            sourceURL = item.sources.first?.url
            sourceLine = AgentNewsSourceLine(sources: item.sources)
            self.time = time
        }

        /// The post at the top of a digest discussion: the digest's time in its header and its headlines in a line
        init(digest: ApiAgentV2ThreadDigestCard) {
            accessibilityIdentifier = "AgentDigestPost-\(digest.id)"
            header = L10n.agentDigestPostHeader(time: AgentNewsFeedCardCell.timeText(for: digest.windowEnd))
            headline = lang("$agent_digest_title")
            body = digest.top.map(\.headline).joined(separator: " · ").nilIfEmpty
            imageURL = nil
            sourceURL = nil
            sourceLine = nil
            time = AgentNewsMetaView.formatDiscussionTime(for: digest.windowEnd)
        }

        var canOpenSource: Bool {
            AgentTextLinks.newsSourceURL(sourceURL) != nil
        }

        var copyText: String {
            AgentTextLinks.newsCopyText(headline: headline, body: body, sourceURL: sourceURL)
        }
    }

    private enum Metrics {
        /// The feed card's and the web's padding around the text
        static let textInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: AgentNewsMetaView.bottomInset, trailing: 16)
        static let headerInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16)
        static let footerSpacing: CGFloat = 8
        static let sourceLineSpacing: CGFloat = 4
        static let imageAspectRatio: CGFloat = 9 / 16
    }

    /// The width the text leaves in a bubble `width` wide
    static func getTextWidth(inBubbleWidth width: CGFloat) -> CGFloat {
        width - Metrics.textInsets.leading - Metrics.textInsets.trailing
    }

    var contextMenuConfigurationProvider: (() -> ContextMenuConfiguration?)?
    var onPreferredHeightChanged: (() -> Void)?
    /// Opens a source's link, the first source's for the post's Open Source
    var openSourceAction: ((String) -> Void)?
    /// A tap on the loaded picture, with the view that shows it
    var onPictureTap: ((UIImageView) -> Void)?

    let bubbleView = AgentBubbleBackgroundView()
    let imageView = WImageView()
    let metaView = AgentNewsMetaView()
    private(set) var content: Content?
    private(set) var hasTail = true
    private(set) var isHeaderVisible = false

    private let postStack = UIStackView()
    /// The header, the picture and the text: what VoiceOver reads as the post
    private let contentStack = UIStackView()
    private let headerContainer = UIStackView()
    private let headerLabel = UILabel()
    /// Holds the picture a point inside the bubble's sides, so a picture as dark or as light as the bubble never merges
    /// with it
    private let imageContainer = UIView()
    private let textStack = UIStackView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    /// The body when it holds a table or code, which stand apart from the text as they do in an answer
    private let bodyRichView = AgentRichMessageView()
    private let sourceLineLabel = AgentNewsSourceLineLabel()
    private var bodyBlocks: [AgentMessageBlock]?
    private var bodyRichWidth: CGFloat = 0
    private weak var footerView: UIView?
    private var imageURL: URL?
    private lazy var imageTopConstraint = imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor)
    private lazy var imageZoom = ImagePinchZoom(imageView: imageView)
    private lazy var contextMenuInteraction = ContextMenuInteraction(
        triggers: .longPress,
        sourcePortal: ContextMenuSourcePortal(mask: .customAttachmentPath { [weak self] attachmentRect in
            self?.bubbleView.makePreviewPath(in: attachmentRect) ?? CGPath(rect: attachmentRect, transform: nil)
        }),
        pressAnimation: .default(transformMode: .sublayerTransform),
        // As on Telegram's comments button, a long press on the footer keeps to it and leaves the menu closed
        activationHitTestProvider: { [weak self] sourceView, point in
            guard let footer = self?.footerView, !footer.isHidden else { return true }
            return !footer.bounds.contains(footer.convert(point, from: sourceView))
        }
    ) { [weak self] _ in
        self?.contextMenuConfigurationProvider?()
    }
    private lazy var openSourceAccessibilityAction = UIAccessibilityCustomAction(name: lang("$agent_news_open_source")) { [weak self] _ in
        guard let self, let url = self.content?.sourceURL else { return false }
        self.openSourceAction?(url)
        return true
    }
    private lazy var moreActionsAccessibilityAction = UIAccessibilityCustomAction(name: lang("More actions")) { [weak self] _ in
        self?.presentMenu()
        return true
    }

    /// The element VoiceOver reads as the post
    var accessibilityContentElement: UIView { contentStack }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with content: Content, isHeaderVisible: Bool) {
        self.content = content
        setHeaderVisible(isHeaderVisible)
        headerLabel.text = content.header
        headlineLabel.text = content.headline
        renderBody()
        // The headline stands as far from the body as paragraphs a blank line apart do
        textStack.setCustomSpacing(
            content.body == nil ? Metrics.footerSpacing : AgentMessageTextRenderer.blankLineGap,
            after: headlineLabel
        )
        sourceLineLabel.configure(with: content.sourceLine)
        metaView.configure(time: content.time)

        updateAccessibilityLabel()
        contentStack.accessibilityIdentifier = content.accessibilityIdentifier
        contentStack.accessibilityCustomActions = [
            content.canOpenSource ? openSourceAccessibilityAction : nil,
            moreActionsAccessibilityAction,
        ].compactMap { $0 } + makeSourceAccessibilityActions(for: content.sourceLine)

        let url = content.imageURL
        guard imageURL != url else { return }
        imageURL = url
        setImageHidden(url == nil)
        imageView.loadImage(url: url) { [weak self] didLoad in
            guard let self, self.imageURL == url, !didLoad, !self.imageView.isHidden else { return }
            self.setImageHidden(true)
            self.preferredHeightChanged()
        }
    }

    func prepareForReuse() {
        content = nil
        headlineLabel.text = nil
        bodyLabel.attributedText = nil
        clearRichBody()
        sourceLineLabel.configure(with: nil)
        metaView.reset()
        imageURL = nil
        imageView.alpha = 1
        imageView.loadImage(url: nil)
        setImageHidden(true)
        contentStack.accessibilityLabel = nil
        contentStack.accessibilityIdentifier = nil
        contentStack.accessibilityCustomActions = nil
        contextMenuConfigurationProvider = nil
        onPreferredHeightChanged = nil
        openSourceAction = nil
        onPictureTap = nil
        alpha = 1
    }

    /// Puts `footer` at the bubble's foot, under the text
    func setFooter(_ footer: UIView) {
        footerView?.removeFromSuperview()
        footerView = footer
        postStack.addArrangedSubview(footer)
    }

    /// Without a tail while something hangs from the post; the tail grows back as it goes
    func setHasTail(_ hasTail: Bool, shouldAnimate: Bool) {
        self.hasTail = hasTail
        bubbleView.configure(
            direction: .incoming,
            fillColor: .air.agentBubbleFill,
            showsTail: hasTail,
            shouldAnimateTail: shouldAnimate && window != nil
        )
    }

    /// How far the post's tail hangs below the bubble's body
    var tailOverflow: CGFloat { hasTail ? AgentBubbleBackgroundView.tailBottomOverflow : 0 }

    /// Wraps the headline and the body at the width a bubble `width` wide gives them, known before the bubble is laid
    /// out: wrapped at whatever width they had before, they would be measured a line short or long
    func updateTextMaxWidth(forBubbleWidth width: CGFloat) {
        let textWidth = Self.getTextWidth(inBubbleWidth: width)
        guard textWidth > 0 else { return }
        for label in [headlineLabel, bodyLabel, sourceLineLabel] where abs(label.preferredMaxLayoutWidth - textWidth) > 0.25 {
            label.preferredMaxLayoutWidth = textWidth
        }
        if let bodyBlocks, abs(bodyRichWidth - textWidth) > 0.25 {
            configureRichBody(bodyBlocks, width: textWidth)
        }
    }

    /// The bubble's body without its tail and its frame in the window, for a picture of the post that flies elsewhere
    func makeFlightSnapshot() -> (view: UIView, frame: CGRect)? {
        guard let window else { return nil }
        let body = bubbleView.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: tailOverflow, right: 0))
        guard let snapshot = bubbleView.resizableSnapshotView(from: body, afterScreenUpdates: false, withCapInsets: .zero) else {
            return nil
        }
        return (snapshot, bubbleView.convert(body, to: window))
    }

    func presentMenu() {
        contextMenuInteraction.present()
    }

    func updateForContentSizeCategoryChange() {
        guard content != nil else { return }
        renderBody()
        preferredHeightChanged()
    }

    private func setHeaderVisible(_ isVisible: Bool) {
        isHeaderVisible = isVisible
        headerContainer.isHidden = !isVisible
        // A picture at the top of the bubble keeps a point of it above, and its top corners follow the bubble's
        imageTopConstraint.constant = isVisible ? 0 : AgentNewsImageMetrics.inset
        let cornerRadius = isVisible ? 0 : AgentNewsImageMetrics.topCornerRadius
        imageView.layer.cornerRadius = cornerRadius
        imageZoom.cornerRadius = cornerRadius
    }

    /// The post as VoiceOver reads it, once its body is drawn: a body with blocks waits for the bubble's width
    private func updateAccessibilityLabel() {
        guard let content else { return }
        contentStack.accessibilityLabel = [
            isHeaderVisible ? content.header : nil,
            content.headline,
            bodyBlocks == nil ? bodyLabel.attributedText?.string : bodyRichView.displayText,
            content.sourceLine?.text,
            content.time,
        ].compactMap { $0?.nilIfEmpty }.joined(separator: ", ")
    }

    /// An action named after each source the line links, opening it as a tap on its name does
    private func makeSourceAccessibilityActions(for line: AgentNewsSourceLine?) -> [UIAccessibilityCustomAction] {
        guard let line else { return [] }
        return line.links.map { link in
            UIAccessibilityCustomAction(name: (line.text as NSString).substring(with: link.range)) { [weak self] _ in
                self?.openSourceAction?(link.url)
                return true
            }
        }
    }

    private func setImageHidden(_ isHidden: Bool) {
        imageView.isHidden = isHidden
        imageContainer.isHidden = isHidden
    }

    /// Parses the body once for every post that shows it, as a chat lays out each answer once
    private func renderBody() {
        guard let body = content?.body else {
            bodyLabel.attributedText = nil
            bodyLabel.isHidden = true
            clearRichBody()
            return
        }
        let blocks = AgentMessageBlockParser.separatingCode(AgentMessageBlockParser.parse(body))
        if blocks.contains(where: \.standsApart) {
            bodyLabel.attributedText = nil
            bodyLabel.isHidden = true
            bodyBlocks = blocks
            bodyRichView.isHidden = false
            configureRichBody(blocks, width: headlineLabel.preferredMaxLayoutWidth)
            return
        }
        clearRichBody()
        bodyLabel.isHidden = false
        let key = Self.getBodyKey(for: body, traitCollection: traitCollection)
        bodyLabel.attributedText = AgentTextLayoutCache.shared.getAttributedText(for: key) {
            AgentMessageTextRenderer.makeAttributedText(
                body,
                textColor: key.textColor,
                rendersMarkdown: key.rendersMarkdown,
                detectsLinks: key.detectsLinks,
                markdownProfile: key.markdownProfile,
                baseFont: key.font
            )
        }
    }

    private func configureRichBody(_ blocks: [AgentMessageBlock], width: CGFloat) {
        // Before the bubble's width is known the blocks wait for `updateTextMaxWidth`
        guard width > 0 else { return }
        bodyRichWidth = width
        bodyRichView.configure(
            blocks: blocks,
            textColor: .label,
            maximumContentWidth: width,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            baseFont: WTypography.uiFont(.body, scaling: .dynamic, compatibleWith: traitCollection),
            onURLTap: nil
        )
        updateAccessibilityLabel()
    }

    private func clearRichBody() {
        guard bodyBlocks != nil else { return }
        bodyBlocks = nil
        bodyRichWidth = 0
        bodyRichView.isHidden = true
        bodyRichView.configure(
            blocks: [],
            textColor: .label,
            maximumContentWidth: 1,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            onURLTap: nil
        )
    }

    /// What the parsed `body` is kept under for posts shown with `traitCollection`
    static func getBodyKey(for body: String, traitCollection: UITraitCollection) -> AgentTextLayoutCache.Key {
        AgentTextLayoutCache.Key(
            text: body,
            textColor: .label,
            linkColor: .tintColor,
            font: WTypography.uiFont(.body, scaling: .dynamic, compatibleWith: traitCollection),
            rendersMarkdown: true,
            markdownProfile: .agentMarkdownV1,
            detectsLinks: false,
            maxWidth: 0
        )
    }

    private func preferredHeightChanged() {
        guard content != nil else { return }
        superview?.setNeedsLayout()
        onPreferredHeightChanged?()
    }

    @objc private func handlePictureTap() {
        guard imageView.image != nil, !imageView.isHidden else { return }
        onPictureTap?(imageView)
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)
        setHasTail(true, shouldAnimate: false)
        contextMenuInteraction.attach(to: bubbleView)

        let iconView = AgentNewsIconView(size: 20)
        headerLabel.applyTextStyle(.subheadlineStrong, scaling: .dynamic)
        headerLabel.textColor = .tintColor
        headerLabel.numberOfLines = 0
        let headerRow = UIStackView(arrangedSubviews: [iconView, headerLabel])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 6
        headerContainer.addArrangedSubview(headerRow)
        headerContainer.alignment = .leading
        headerContainer.isLayoutMarginsRelativeArrangement = true
        headerContainer.insetsLayoutMarginsFromSafeArea = false
        headerContainer.directionalLayoutMargins = Metrics.headerInsets
        // Keep the header at its content height while a self-sizing row is measured or loses follow-ups.
        headerContainer.heightAnchor.constraint(equalToConstant: 0).withPriority(.defaultLow).isActive = true
        headerContainer.isHidden = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .air.secondaryFill
        imageView.isAccessibilityElement = false
        imageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        imageView.layer.cornerCurve = .continuous
        // The picture's own pixel size never sizes the post, and the picture gives way rather than any text when the
        // row's height comes out a fraction of a point short as the layout rounds to pixels: a label a third of a point
        // shorter than its text drops its last line
        imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: Metrics.imageAspectRatio)
            .withPriority(UILayoutPriority(700)).isActive = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageTopConstraint,
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: AgentNewsImageMetrics.inset),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -AgentNewsImageMetrics.inset),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
        ])
        imageZoom.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePictureTap)))
        setImageHidden(true)

        headlineLabel.applyTextStyle(.bodyStrong, scaling: .dynamic)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 0
        bodyLabel.numberOfLines = 0
        // As Telegram's message status, the time sits in the bubble's bottom trailing corner, nearer the bubble's edge
        // than the text does
        let footerRow = UIView()
        metaView.translatesAutoresizingMaskIntoConstraints = false
        footerRow.addSubview(metaView)
        NSLayoutConstraint.activate([
            metaView.topAnchor.constraint(equalTo: footerRow.topAnchor),
            metaView.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor),
            metaView.leadingAnchor.constraint(greaterThanOrEqualTo: footerRow.leadingAnchor),
            metaView.trailingAnchor.constraint(
                equalTo: footerRow.trailingAnchor,
                constant: Metrics.textInsets.trailing - AgentNewsMetaView.trailingInset
            ),
        ])
        // The row holds its height only weakly, so it is kept as short as its text, or a post measured against a taller
        // height would stretch it
        footerRow.heightAnchor.constraint(equalToConstant: 0).withPriority(.defaultLow).isActive = true
        bodyRichView.isHidden = true
        sourceLineLabel.onLinkTap = { [weak self] url in self?.openSourceAction?(url) }
        for view in [headlineLabel, bodyLabel, bodyRichView, sourceLineLabel, footerRow] { textStack.addArrangedSubview(view) }
        textStack.axis = .vertical
        textStack.spacing = Metrics.footerSpacing
        textStack.setCustomSpacing(Metrics.sourceLineSpacing, after: sourceLineLabel)
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.insetsLayoutMarginsFromSafeArea = false
        textStack.directionalLayoutMargins = Metrics.textInsets

        for view in [headerContainer, imageContainer, textStack] { contentStack.addArrangedSubview(view) }
        contentStack.axis = .vertical
        contentStack.isAccessibilityElement = true
        contentStack.accessibilityTraits = .staticText
        postStack.addArrangedSubview(contentStack)
        postStack.axis = .vertical
        postStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.contentView.addSubview(postStack)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),
            postStack.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor),
            postStack.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor),
            postStack.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor),
            postStack.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor),
        ])
        isAccessibilityElement = false
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: AgentNewsPostView, _) in
                view.updateForContentSizeCategoryChange()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
            updateForContentSizeCategoryChange()
        }
    }
}

/// The design's news picture: a point inside its bubble on every side it meets, its corners there rounded a point less
/// than the bubble's
enum AgentNewsImageMetrics {
    static let inset: CGFloat = 1
    static let topCornerRadius: CGFloat = 20 - inset
}
