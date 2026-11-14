import BigInt
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The News avatar: the Agent's gradient, as the unread mark has it, with a white pulse
final class AgentNewsIconView: UIView {
    private let avatarView = AgentThreadAvatarView()

    init(size: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.configureNews()
        addSubview(avatarView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The News row: the latest headline with its picture, its date in the list's date style and Telegram's counter of the
/// unread news, or in the Digests view of the unread digests
final class AgentNewsCell: AgentThreadRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "AgentMyPulseRow"
        avatarView.configureNews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The most unread items the counter shows; more show the unread dot
    private static let unreadCountMax = 10

    func configure(latestNews: ApiAgentV2NewsFeedItem?, unreadCount: Int, now: Date = .now) {
        configure(
            headline: latestNews?.headline,
            imageUrl: latestNews?.imageUrl,
            time: Self.formatTime(latestNews?.deliveredAt, now: now),
            unreadCount: unreadCount,
            unreadDescription: unreadCount > 0 ? L10n.agentNewsUnreadCount(count: unreadCount) : nil
        )
    }

    /// The row of the Digests view: the latest digest's first headline with its picture, the digest's time and the
    /// counter of the unread digests
    func configure(latestDigest: ApiAgentV2NewsFeedDigest, unreadCount: Int, now: Date = .now) {
        configure(
            headline: latestDigest.top.first?.headline,
            imageUrl: latestDigest.top.first?.imageUrl,
            time: Self.formatTime(latestDigest.deliveredAt, now: now),
            unreadCount: unreadCount,
            unreadDescription: unreadCount > 0 ? L10n.agentNewsUnreadDigestsCount(count: unreadCount) : nil
        )
    }

    private func configure(
        headline: String?,
        imageUrl: String?,
        time: String?,
        unreadCount: Int,
        unreadDescription: String?
    ) {
        setTexts(
            title: lang("News"),
            preview: headline ?? lang("Crypto Market News"),
            time: time
        )
        setPreviewImage(url: imageUrl.flatMap(URL.init(string:)))
        if unreadCount > Self.unreadCountMax {
            unreadMark = .dot
        } else {
            unreadMark = unreadCount > 0 ? .count(formatBigIntText(BigInt(unreadCount), tokenDecimals: 0)) : nil
        }
        accessibilityLabel = [titleLabel.text, previewLabel.text, timeLabel.text, unreadDescription]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: ", ")
    }

    private static func formatTime(_ deliveredAt: String?, now: Date) -> String? {
        deliveredAt.map {
            AgentThreadDateFormatting.formatRowTimestamp(for: $0, shouldShowDateWhenNotToday: true, relativeTo: now)
        }
    }
}

/// The Agent's round marks: cyan from the upper left spreading into purple toward the lower right
enum AgentMarkGradient {
    static func apply(to layer: CAGradientLayer) {
        layer.type = .radial
        layer.colors = [UIColor(hex: "#00BEFF").cgColor, UIColor(hex: "#B656FF").cgColor]
        layer.startPoint = CGPoint(x: 0.3, y: 0.3)
        layer.endPoint = CGPoint(x: 1.1, y: 1.1)
    }
}

/// How a list row marks what is unread in it
enum AgentUnreadMark: Equatable {
    case dot
    /// Telegram's counter of the unread items, with `text` as its digits
    case count(String)
}

/// The unread mark of the list on Agent's blue-to-purple gradient: a dot, or Telegram's counter with `countText`
final class AgentUnreadBadgeView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let countLabel = UILabel()

    var countText: String? {
        didSet {
            guard countText != oldValue else { return }
            countLabel.text = countText
            countLabel.isHidden = countText == nil
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        AgentMarkGradient.apply(to: gradientLayer)
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull()]
        layer.addSublayer(gradientLayer)
        countLabel.font = AgentThreadRowMetrics.unreadCounterFont
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.isHidden = true
        addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard let countText else {
            return CGSize(width: AgentThreadRowMetrics.unreadDotSize, height: AgentThreadRowMetrics.unreadDotSize)
        }
        let textWidth = ceil((countText as NSString).size(withAttributes: [.font: AgentThreadRowMetrics.unreadCounterFont]).width)
        let height = AgentThreadRowMetrics.unreadCounterHeight
        return CGSize(width: max(height, textWidth + AgentThreadRowMetrics.unreadCounterHorizontalPadding), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = min(bounds.width, bounds.height) / 2
        countLabel.frame = bounds
    }
}
