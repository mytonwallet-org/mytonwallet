import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The colors of live support, as in Classic: the green of support over the theme's own colors
enum AgentSupportColors {
    /// An operator's bubble: the incoming bubble with 13% of the theme's green over it
    static let operatorBubbleFill = UIColor { traits in
        blend(UIColor.air.agentBubbleFill, UIColor.air.positiveAmount, fraction: 0.13, traits: traits)
    }
    static let badgeText = UIColor.air.positiveAmount
    static let badgeFill = UIColor.air.positiveAmount.withAlphaComponent(0.16)
    /// The operator's initial stands on this when they have no photo, as in Classic
    static let operatorInitialFill = UIColor(hex: "#D9895B")

    private static func blend(_ base: UIColor, _ overlay: UIColor, fraction: CGFloat, traits: UITraitCollection) -> UIColor {
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        base.resolvedColor(with: traits).getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
        overlay.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: baseRed + (red - baseRed) * fraction,
            green: baseGreen + (green - baseGreen) * fraction,
            blue: baseBlue + (blue - baseBlue) * fraction,
            alpha: baseAlpha
        )
    }
}

/// The headset that marks support in the chat and the chat list, drawn as Classic draws it
enum AgentSupportIcon {
    private static let designSize: CGFloat = 24
    private static let lineWidth: CGFloat = 2.4

    static func makeImage(size: CGFloat) -> UIImage {
        let scale = size / designSize
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let path = UIBezierPath()
            // The band over the head
            path.move(to: CGPoint(x: 4, y: 14))
            path.addLine(to: CGPoint(x: 4, y: 12))
            path.addArc(withCenter: CGPoint(x: 12, y: 12), radius: 8, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: 20, y: 14))
            // The ear cups
            path.move(to: CGPoint(x: 4, y: 14))
            path.addLine(to: CGPoint(x: 7, y: 14))
            path.addLine(to: CGPoint(x: 7, y: 19))
            path.addLine(to: CGPoint(x: 5, y: 19))
            path.addArc(withCenter: CGPoint(x: 5, y: 18), radius: 1, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
            path.close()
            path.move(to: CGPoint(x: 20, y: 14))
            path.addLine(to: CGPoint(x: 17, y: 14))
            path.addLine(to: CGPoint(x: 17, y: 19))
            path.addLine(to: CGPoint(x: 19, y: 19))
            path.addArc(withCenter: CGPoint(x: 19, y: 18), radius: 1, startAngle: .pi / 2, endAngle: 0, clockwise: false)
            path.close()
            path.apply(CGAffineTransform(scaleX: scale, y: scale))
            path.lineWidth = lineWidth * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// The author over an answer once an operator has joined the chat: the operator's photo, name and support badge, or
/// the Agent's mark and name, so that the user tells the two apart
final class AgentMessageAuthorView: UIView {
    static let avatarSize: CGFloat = 28
    private static let markSize: CGFloat = 16
    private static let spacing: CGFloat = 8
    private static let badgeInsets = UIEdgeInsets(top: 1, left: 7, bottom: 1, right: 7)

    private let avatarView = UIView()
    private let photoView = WImageView()
    private let initialLabel = UILabel()
    private let markView = UIImageView(image: AgentSpinningTopIcon.makeTemplateImage(size: AgentMessageAuthorView.markSize))
    private let nameLabel = UILabel()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private var photoURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `author`, or the Agent for an answer of the Agent's
    func configure(author: AgentMessage.Author) {
        guard case .operator(let operatorAuthor) = author else {
            avatarView.backgroundColor = .tintColor
            markView.isHidden = false
            initialLabel.isHidden = true
            photoView.isHidden = true
            photoURL = nil
            photoView.loadImage(url: nil)
            nameLabel.text = lang("Agent")
            badgeView.isHidden = true
            accessibilityLabel = nameLabel.text
            return
        }
        avatarView.backgroundColor = AgentSupportColors.operatorInitialFill
        markView.isHidden = true
        initialLabel.text = operatorAuthor.name.trimmingCharacters(in: .whitespacesAndNewlines).first
            .map { String($0).uppercased() }
        nameLabel.text = operatorAuthor.name
        badgeLabel.text = L10n.agentSupportBadge(appName: APP_NAME)
        badgeView.isHidden = false
        accessibilityLabel = [operatorAuthor.name, badgeLabel.text ?? ""].joined(separator: ", ")
        showPhoto(at: operatorAuthor.avatarUrl.flatMap(URL.init(string:)))
    }

    /// The photo shows once it has loaded; without one, or when it fails to load, the initial shows
    private func showPhoto(at url: URL?) {
        guard url != photoURL || initialLabel.isHidden == photoView.isHidden else { return }
        photoURL = url
        photoView.isHidden = true
        initialLabel.isHidden = false
        guard let url else {
            photoView.loadImage(url: nil)
            return
        }
        photoView.loadImage(url: url) { [weak self] didLoad in
            guard let self, self.photoURL == url else { return }
            self.photoView.isHidden = !didLoad
            self.initialLabel.isHidden = didLoad
        }
    }

    private func setupViews() {
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        let stackView = UIStackView(arrangedSubviews: [avatarView, nameLabel, badgeView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Self.spacing
        addSubview(stackView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        avatarView.clipsToBounds = true
        for view in [initialLabel, markView, photoView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            avatarView.addSubview(view)
        }
        initialLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center
        markView.tintColor = .white
        markView.contentMode = .center
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.isHidden = true

        nameLabel.font = .systemFont(ofSize: 14, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.backgroundColor = AgentSupportColors.badgeFill
        badgeView.layer.cornerRadius = 6
        badgeView.layer.cornerCurve = .continuous
        badgeView.addSubview(badgeLabel)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = AgentSupportColors.badgeText
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            initialLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            markView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            markView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            photoView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            photoView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),
            photoView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            badgeLabel.topAnchor.constraint(equalTo: badgeView.topAnchor, constant: Self.badgeInsets.top),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: -Self.badgeInsets.bottom),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: Self.badgeInsets.left),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -Self.badgeInsets.right),
        ])
    }
}

/// The label of a chat with support before its preview in the chat list: the headset and "Support", in the accent
/// color on its tint while an operator is in the chat, in gray while the chat waits for one
final class AgentSupportLabelView: UIView {
    static let spacing: CGFloat = 6
    private static let iconSize: CGFloat = 12
    private static let insets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)

    private let iconView = UIImageView(image: AgentSupportIcon.makeImage(size: AgentSupportLabelView.iconSize))
    private let label = UILabel()
    private var style: AgentSupportPresentation.LabelStyle = .muted

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String? { label.text }

    func configure(style: AgentSupportPresentation.LabelStyle) {
        self.style = style
        label.text = lang("$agent_support_label")
        updateColors()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateColors()
        }
    }

    private func updateColors() {
        let color: UIColor = style == .active ? tintColor : AgentThreadRowMetrics.secondaryTextColor
        iconView.tintColor = color
        label.textColor = color
        backgroundColor = style == .active ? tintColor.withAlphaComponent(0.12) : .air.agentHintBackground
    }

    private func setupViews() {
        isAccessibilityElement = false
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 3
        addSubview(stackView)
        label.font = .systemFont(ofSize: 12, weight: .bold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Self.insets.top),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.insets.bottom),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.insets.left),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.insets.right),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])
    }
}
