import UIKit
import UIComponents
import WalletContext
import WalletCore

/// A digest's top headlines, as its card in the feed and its post at the top of its discussion show them: one row for
/// each, with a bullet, the headline and a gray disclosure arrow, a separator between rows, then the news it leaves out.
/// A row opens its news item's discussion.
///
/// When a headline has its news item's picture, every row leads with a square in place of the bullet: the picture, a
/// target of its own that opens the digest's pictures in the media viewer, or the News mark for a headline without one
/// or whose picture fails. VoiceOver opens a picture that has loaded through an action of its row.
///
/// The arrows stand as far from the bubble's edge as the Discuss strip's: the rows run `arrowOverhang` past the view's
/// trailing edge, into the bubble's text inset.
final class AgentNewsDigestHeadlinesView: UIView {
    private enum Metrics {
        static let headlineMinimumHeight: CGFloat = 44
        static let headlineVerticalInset: CGFloat = 10
        static let bulletSize: CGFloat = 6
        static let bulletSpacing: CGFloat = 10
        static let thumbnailSize: CGFloat = 40
        static let thumbnailSpacing: CGFloat = 12
        static let thumbnailCornerRadius: CGFloat = 10
        static let newsMarkSize: CGFloat = 20
        static let remainderTopInset: CGFloat = 4
    }

    /// The bubble's text inset is 16 pt and the Discuss strip's arrow box ends 9 pt from the bubble's edge
    static let arrowOverhang: CGFloat = 16 - AgentNewsDiscussionMetrics.arrowTrailingInset

    /// A tap on the headline of the news item with this event ID
    var headlineAction: ((Int) -> Void)?
    /// A picture loaded or failed, so the actions that open the pictures changed
    var onPicturesChanged: (() -> Void)?

    private(set) var headlineButtons: [AgentNewsDimmingButton] = []
    /// The pictures of the headlines that have one, in the headlines' order
    private(set) var thumbnails: [Thumbnail] = []
    private(set) var hasThumbnails = false
    private var headlines: [ApiAgentV2DigestHeadline] = []
    private var headlineLabels: [UILabel] = []
    private var date = Date.distantPast
    private var textMaxWidth: CGFloat = 0
    let remainderLabel = UILabel()
    private let stackView = UIStackView()
    private let remainderContainer = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasRemainder: Bool { !remainderContainer.isHidden }

    /// `date` is when the digest came, as the media viewer dates its pictures
    func configure(headlines: [ApiAgentV2DigestHeadline], remainder: String?, date: Date) {
        self.date = date
        remainderLabel.text = remainder
        remainderContainer.isHidden = remainder == nil
        // The rows stay as they are for the same headlines, so their pictures don't load again
        if headlines != self.headlines {
            removeHeadlines()
            self.headlines = headlines
            hasThumbnails = headlines.contains { $0.imageURL != nil }
            headlineButtons = headlines.enumerated().map { index, headline in
                if index > 0 { stackView.insertArrangedSubview(makeSeparator(), at: stackView.arrangedSubviews.count - 1) }
                let button = makeHeadlineButton(headline)
                stackView.insertArrangedSubview(button, at: stackView.arrangedSubviews.count - 1)
                return button
            }
            remainderContainer.directionalLayoutMargins.leading = textLeading
        }
        updateTextMaxWidth(textMaxWidth)
    }

    /// Lets the headlines go, with the pictures still loading for them
    func prepareForReuse() {
        removeHeadlines()
        remainderLabel.text = nil
        remainderContainer.isHidden = true
    }

    /// Wraps the headlines at the width a view `width` wide gives them, known before it is laid out
    func updateTextMaxWidth(_ width: CGFloat) {
        textMaxWidth = width
        guard width > 0 else { return }
        let arrowWidth = AgentNewsDiscussionMetrics.arrowSpacing + AgentNewsDiscussionMetrics.arrowBoxSize.width
        for label in headlineLabels {
            label.preferredMaxLayoutWidth = max(0, width + Self.arrowOverhang - textLeading - arrowWidth)
        }
        remainderLabel.preferredMaxLayoutWidth = max(0, width - textLeading)
    }

    // The rows reach past the trailing edge by `arrowOverhang`, and a tap there still opens the row; a tap on a picture
    // keeps to the picture
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        let overhang = Self.arrowOverhang
        let insets = effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? UIEdgeInsets(top: 0, left: -overhang, bottom: 0, right: 0)
            : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -overhang)
        if let button = headlineButtons.first(where: { $0.convert($0.bounds, to: self).inset(by: insets).contains(point) }) {
            return button.hitTest(button.convert(point, from: self), with: event) ?? button
        }
        return super.hitTest(point, with: event)
    }

    /// Opens the digest's pictures that haven't failed in the media viewer at `thumbnail`'s, each captioned with its
    /// headline alone and dated with the digest, without the actions and the sources of a news post
    private func openPicture(_ thumbnail: Thumbnail) {
        guard let window else { return }
        let shown = thumbnails.filter { !$0.hasFailed }
        guard let index = shown.firstIndex(where: { $0 === thumbnail }) else { return }
        let (day, time) = AgentModel.formatChatDate(for: date)
        let pictures = shown.map { thumbnail in
            MediaViewer.Picture(
                url: thumbnail.headline.imageURL,
                image: thumbnail.imageView.image,
                title: thumbnail.headline.headline,
                details: MediaViewer.Details(
                    date: "\(day), \(time)",
                    caption: NSAttributedString(string: thumbnail.headline.headline, attributes: [
                        .font: AgentNewsPictureViewer.captionTitleFont,
                        .foregroundColor: UIColor.white,
                    ]),
                    actions: []
                )
            )
        }
        MediaViewer.present(pictures: pictures, index: index, in: window) { [weak self] index in
            let thumbnail = shown[index]
            guard self?.thumbnails.contains(where: { $0 === thumbnail }) == true, thumbnail.isShowingPicture else { return nil }
            return thumbnail.imageView
        }
    }

    /// The action that opens the picture of the headline of `eventId` once it has loaded
    func makePictureAccessibilityAction(eventId: Int) -> UIAccessibilityCustomAction? {
        thumbnails.first { $0.headline.eventId == eventId && $0.isShowingPicture }.map(makePictureAccessibilityAction(for:))
    }

    /// Named after the picture and its headline, as no wording of the app tells opening a picture
    private func makePictureAccessibilityAction(for thumbnail: Thumbnail) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: "\(lang("Picture")), \(thumbnail.headline.headline)") { [weak self, weak thumbnail] _ in
            guard let self, let thumbnail else { return false }
            self.openPicture(thumbnail)
            return true
        }
    }

    private var textLeading: CGFloat {
        hasThumbnails ? Metrics.thumbnailSize + Metrics.thumbnailSpacing : Metrics.bulletSize + Metrics.bulletSpacing
    }

    private func removeHeadlines() {
        for thumbnail in thumbnails { thumbnail.imageView.loadImage(url: nil) }
        thumbnails = []
        stackView.arrangedSubviews.filter { $0 !== remainderContainer }.forEach { $0.removeFromSuperview() }
        headlines = []
        headlineLabels = []
        headlineButtons = []
        hasThumbnails = false
    }

    private func makeHeadlineButton(_ headline: ApiAgentV2DigestHeadline) -> AgentNewsDimmingButton {
        let label = UILabel()
        label.applyTextStyle(.body, scaling: .dynamic)
        label.textColor = .label
        label.numberOfLines = 0
        label.text = headline.headline
        headlineLabels.append(label)
        let arrow = UIImageView(image: AgentNewsDiscussionStrip.arrowImage)
        arrow.tintColor = .air.secondaryLabel
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentCompressionResistancePriority(.required, for: .horizontal)

        let button = AgentNewsDimmingButton()
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.accessibilityLabel = headline.headline
        button.accessibilityIdentifier = "AgentNewsDigestHeadline-\(headline.eventId)"
        button.addAction(UIAction { [weak self] _ in self?.headlineAction?(headline.eventId) }, for: .touchUpInside)

        let content: UIView
        if hasThumbnails {
            content = makeThumbnailRow(for: headline, label: label, arrow: arrow, row: button)
        } else {
            content = makeBulletRow(label: label, arrow: arrow)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)
        button.highlightedContentView = content
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.headlineMinimumHeight),
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: Self.arrowOverhang),
            content.topAnchor.constraint(equalTo: button.topAnchor, constant: Metrics.headlineVerticalInset),
            content.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -Metrics.headlineVerticalInset),
        ])
        return button
    }

    /// A bullet by the headline's first line and the arrow
    private func makeBulletRow(label: UILabel, arrow: UIImageView) -> UIView {
        let bullet = UIView()
        bullet.backgroundColor = .tintColor
        bullet.layer.cornerRadius = Metrics.bulletSize / 2
        bullet.translatesAutoresizingMaskIntoConstraints = false
        let bulletBox = UIView()
        bulletBox.addSubview(bullet)
        let row = makeRow([bulletBox, label, arrow], spacing: Metrics.bulletSpacing, after: label)
        row.alignment = .center
        NSLayoutConstraint.activate([
            bulletBox.widthAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.widthAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.heightAnchor.constraint(equalToConstant: Metrics.bulletSize),
            bullet.centerXAnchor.constraint(equalTo: bulletBox.centerXAnchor),
            // The bullet stands by the headline's first line
            bullet.centerYAnchor.constraint(equalTo: label.firstBaselineAnchor, constant: -label.font.xHeight / 2),
            bulletBox.heightAnchor.constraint(equalTo: row.heightAnchor),
        ])
        return row
    }

    /// The square at the top of the row, which shows the headline's picture over its loading fill or the News mark, the
    /// headline centred on it while shorter and from its top when taller, and the arrow in the row's middle. The picture
    /// lies over the square apart from the row, so a tap on it opens it and not the news item's discussion.
    private func makeThumbnailRow(
        for headline: ApiAgentV2DigestHeadline,
        label: UILabel,
        arrow: UIImageView,
        row button: AgentNewsDimmingButton
    ) -> UIView {
        let tile = UIView()
        tile.backgroundColor = .air.secondaryFill
        tile.layer.cornerRadius = Metrics.thumbnailCornerRadius
        tile.layer.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false
        let newsMark = AgentNewsIconView(size: Metrics.newsMarkSize)
        tile.addSubview(newsMark)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        let arrowBox = UIView()
        arrowBox.addSubview(arrow)
        let row = makeRow([tile, label, arrowBox], spacing: Metrics.thumbnailSpacing, after: label)
        row.alignment = .top
        let content = AgentNewsDigestRowContentView()
        content.addSubview(row)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: Metrics.thumbnailSize),
            tile.heightAnchor.constraint(equalToConstant: Metrics.thumbnailSize),
            // A label draws its lines in the middle of its height
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.thumbnailSize),
            newsMark.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            newsMark.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            arrowBox.heightAnchor.constraint(equalTo: row.heightAnchor),
            arrow.leadingAnchor.constraint(equalTo: arrowBox.leadingAnchor),
            arrow.trailingAnchor.constraint(equalTo: arrowBox.trailingAnchor),
            arrow.centerYAnchor.constraint(equalTo: arrowBox.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        guard let url = headline.imageURL else { return content }

        newsMark.isHidden = true
        let thumbnail = Thumbnail(headline: headline)
        thumbnails.append(thumbnail)
        let thumbnailButton = thumbnail.button
        thumbnailButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(thumbnailButton)
        NSLayoutConstraint.activate([
            thumbnailButton.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            thumbnailButton.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            thumbnailButton.topAnchor.constraint(equalTo: tile.topAnchor),
            thumbnailButton.bottomAnchor.constraint(equalTo: tile.bottomAnchor),
        ])
        thumbnailButton.addAction(UIAction { [weak self, weak thumbnail] _ in
            guard let self, let thumbnail else { return }
            self.openPicture(thumbnail)
        }, for: .touchUpInside)
        thumbnail.imageView.loadImage(url: url) { [weak self, weak thumbnail, weak newsMark, weak button] didLoad in
            guard let self, let thumbnail else { return }
            thumbnail.setLoaded(didLoad)
            newsMark?.isHidden = didLoad
            button?.accessibilityCustomActions = didLoad ? [self.makePictureAccessibilityAction(for: thumbnail)] : nil
            self.onPicturesChanged?()
        }
        return content
    }

    private func makeRow(_ views: [UIView], spacing: CGFloat, after label: UILabel) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = spacing
        row.setCustomSpacing(AgentNewsDiscussionMetrics.arrowSpacing, after: label)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .air.separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return separator
    }

    private func configureViews() {
        remainderLabel.applyTextStyle(.subheadline, scaling: .dynamic)
        remainderLabel.textColor = .air.secondaryLabel
        remainderLabel.numberOfLines = 0
        remainderContainer.addArrangedSubview(remainderLabel)
        remainderContainer.isLayoutMarginsRelativeArrangement = true
        remainderContainer.insetsLayoutMarginsFromSafeArea = false
        remainderContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.remainderTopInset, leading: textLeading, bottom: 0, trailing: 0
        )
        remainderContainer.isHidden = true
        stackView.addArrangedSubview(remainderContainer)
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

extension AgentNewsDigestHeadlinesView {
    /// A headline's picture over its square, which takes taps once it shows the picture and dims under the finger as
    /// the row does. A picture that fails leaves the square to the News mark, and the viewer leaves it out.
    @MainActor
    final class Thumbnail {
        let headline: ApiAgentV2DigestHeadline
        let button = AgentNewsDimmingButton()
        let imageView = WImageView()
        private(set) var hasFailed = false

        init(headline: ApiAgentV2DigestHeadline) {
            self.headline = headline
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = Metrics.thumbnailCornerRadius
            imageView.layer.cornerCurve = .continuous
            imageView.isUserInteractionEnabled = false
            imageView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(imageView)
            button.highlightedContentView = imageView
            // Without wording of its own, the picture leaves VoiceOver to its row
            button.isAccessibilityElement = false
            button.accessibilityElementsHidden = true
            // Until the picture shows, a tap on its square opens the row
            button.isUserInteractionEnabled = false
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: button.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }

        var isShowingPicture: Bool { !button.isHidden && imageView.image != nil }

        func setLoaded(_ didLoad: Bool) {
            hasFailed = !didLoad
            button.isHidden = !didLoad
            button.isUserInteractionEnabled = didLoad
        }
    }
}

/// A row that leads with a picture: only the picture takes a touch, and the rest goes to the row's button
private final class AgentNewsDigestRowContentView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

private extension ApiAgentV2DigestHeadline {
    var imageURL: URL? {
        imageUrl?.nilIfEmpty.flatMap(URL.init(string:))
    }
}
