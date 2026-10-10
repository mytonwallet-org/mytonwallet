import SwiftUI
import UIComponents
import UIKit
import WalletContext

@MainActor
class UniversalSearchBaseCell: WHighlightCollectionViewCell {
    let highlightView = WHighlightStackView()

    var usesDefaultSelectedAppearance: Bool { true }
    var isPresentedAsSelected: Bool { isSelected || isPersistentlySelected }
    var isPersistentlySelected = false {
        didSet {
            guard isPersistentlySelected != oldValue else { return }
            refreshSelectionAppearance()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            refreshSelectionAppearance()
        }
    }

    override var isSelected: Bool {
        didSet {
            refreshSelectionAppearance()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = .clear
        baseBackgroundColor = .clear
        highlightBackgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        isAccessibilityElement = true

        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = .clear
        highlightView.highlightBackgroundColor = .air.universalSearchHighlight
        highlightView.highlightingTime = 0.1
        highlightView.unhighlightingTime = 0.5
        highlightView.layer.cornerRadius = 22
        highlightView.layer.cornerCurve = .continuous
        insertSubview(highlightView, at: 0)

        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -16),
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 16),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isPersistentlySelected = false
    }

    func selectionAppearanceDidChange() {}

    func refreshSelectionAppearance() {
        let showsDefaultSelectedAppearance = isPresentedAsSelected && usesDefaultSelectedAppearance
        highlightView.isHighlighted = isHighlighted || showsDefaultSelectedAppearance
        if isPresentedAsSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
        selectionAppearanceDidChange()
    }
}

@MainActor
final class UniversalSearchResolvingDomainCell: UniversalSearchBaseCell {
    override var usesDefaultSelectedAppearance: Bool { false }

    func configure(domain: String) {
        highlightView.backgroundColor = .air.universalSearchHighlight
        contentConfiguration = UIHostingConfiguration {
            HStack(spacing: 8) {
                Circle()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 9) {
                    Capsule()
                        .frame(width: 80, height: 12)
                    Capsule()
                        .frame(width: 128, height: 9)
                }
            }
            .foregroundStyle(Color.air.secondaryLabel.opacity(0.3))
            .mask { LoadingShineMask(isActive: true) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .margins(.all, 0)
        .background(Color.clear)
        accessibilityLabel = "\(domain), \(lang("Loading..."))"
        accessibilityTraits = .updatesFrequently
    }
}

@MainActor
final class UniversalSearchTextResultCell: UniversalSearchBaseCell {
    enum TitleStyle {
        case regular
        case emphasized
    }

    private let iconView = IconView(size: 24, accessoryGeometry: .forIcon24)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private lazy var titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9)
    private lazy var titleCenterConstraint = titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.applyTextStyle(.caption)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleTopConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        icon: UniversalSearchIcon,
        title: String,
        subtitle: String,
        titleStyle: TitleStyle = .emphasized,
        centersTitle: Bool = false
    ) {
        icon.configure(iconView)
        titleLabel.applyTextStyle(titleStyle == .emphasized ? .bodyEmphasized : .body)
        titleLabel.textColor = .label
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = centersTitle
        titleTopConstraint.isActive = !centersTitle
        titleCenterConstraint.isActive = centersTitle
        accessibilityLabel = subtitle.isEmpty ? title : "\(title), \(subtitle)"
        accessibilityTraits = .button
        refreshSelectionAppearance()
    }
}

@MainActor
final class UniversalSearchTokenCell: UniversalSearchBaseCell {
    private let iconView = IconView(size: 24, accessoryGeometry: .forIcon24)
    private let titleLabel = UILabel()
    private let badgeView = BadgeView()
    private let priceLabel = UILabel()
    private let amountLabel = UILabel()
    private let balanceValueLabel = UILabel()
    private let titleRow = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.applyTextStyle(.bodyEmphasized)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badgeView.configureHidden()
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 4
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(badgeView)
        titleRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.applyTextStyle(.caption, content: .technical)
        priceLabel.textColor = .air.secondaryLabel
        priceLabel.lineBreakMode = .byTruncatingMiddle
        priceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.applyTextStyle(.body, content: .technical)
        amountLabel.textColor = .label
        amountLabel.textAlignment = .right
        amountLabel.lineBreakMode = .byTruncatingMiddle
        amountLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        balanceValueLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceValueLabel.applyTextStyle(.caption, content: .technical)
        balanceValueLabel.textColor = .air.secondaryLabel
        balanceValueLabel.textAlignment = .right
        balanceValueLabel.lineBreakMode = .byTruncatingMiddle
        balanceValueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        contentView.addSubview(iconView)
        contentView.addSubview(titleRow)
        contentView.addSubview(priceLabel)
        contentView.addSubview(amountLabel)
        contentView.addSubview(balanceValueLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),
            priceLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            priceLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            priceLabel.trailingAnchor.constraint(lessThanOrEqualTo: balanceValueLabel.leadingAnchor, constant: -8),
            amountLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            amountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleRow.leadingAnchor),
            balanceValueLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            balanceValueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            balanceValueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: priceLabel.leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ result: UniversalSearchTokenResult) {
        result.icon.configure(iconView)
        titleLabel.text = result.title
        priceLabel.text = result.price
        amountLabel.text = result.amount
        balanceValueLabel.text = result.balanceValue
        amountLabel.isHidden = result.amount == nil
        balanceValueLabel.isHidden = result.balanceValue == nil
        if let badge = result.badge {
            badgeView.configureTokenLabel(text: badge, style: .stock)
        } else {
            badgeView.configureHidden()
        }

        let values = [result.title, result.price, result.amount, result.balanceValue]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityLabel = values
        accessibilityTraits = .button
        refreshSelectionAppearance()
    }
}

@MainActor
final class UniversalSearchAppCell: UniversalSearchBaseCell {
    private let iconView = IconView(size: 24, accessoryGeometry: .forIcon24)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let telegramImageView = UIImageView()
    private let actionButton = UIButton(type: .system)
    private let titleRow = UIStackView()
    private var onOpen: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.applyTextStyle(.bodyEmphasized)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        telegramImageView.image = UIImage.airBundle("TelegramLogo20")
        telegramImageView.contentMode = .scaleAspectFit
        telegramImageView.tintColor = UIColor.air.secondaryLabel.withAlphaComponent(0.5)
        telegramImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            telegramImageView.widthAnchor.constraint(equalToConstant: 18),
            telegramImageView.heightAnchor.constraint(equalToConstant: 18),
        ])

        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 4
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(telegramImageView)
        titleRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.applyTextStyle(.caption)
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.cornerStyle = .capsule
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WTypography.uiFont(.supportingBold)
            return outgoing
        }
        actionButton.configuration = buttonConfiguration
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)

        contentView.addSubview(iconView)
        contentView.addSubview(titleRow)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        updateActionButtonColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ result: UniversalSearchAppResult, onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        result.icon.configure(iconView)
        titleLabel.text = result.title
        subtitleLabel.text = result.subtitle
        telegramImageView.isHidden = !result.showsTelegramBadge
        actionButton.configuration?.title = result.actionTitle
        actionButton.isHidden = result.actionTitle == nil
        accessibilityLabel = "\(result.title), \(result.subtitle)"
        accessibilityHint = result.actionTitle
        accessibilityTraits = .button
        refreshSelectionAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onOpen = nil
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateActionButtonColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateActionButtonColors()
    }

    @objc private func openTapped() {
        onOpen?()
    }

    private func updateActionButtonColors() {
        guard var configuration = actionButton.configuration else { return }
        let resolvedTintColor = tintColor.resolvedColor(with: traitCollection)
        let backgroundOpacity: CGFloat = traitCollection.userInterfaceStyle == .dark ? 0.24 : 0.1
        configuration.baseForegroundColor = resolvedTintColor
        configuration.baseBackgroundColor = resolvedTintColor.withAlphaComponent(backgroundOpacity)
        actionButton.configuration = configuration
    }
}

@MainActor
final class UniversalSearchActionCell: UniversalSearchBaseCell {
    enum Kind {
        case agent
        case webSearch

        var systemName: String {
            switch self {
            case .agent:
                "sparkles.2"
            case .webSearch:
                "magnifyingglass"
            }
        }
    }

    override var usesDefaultSelectedAppearance: Bool { kind != .agent }

    private let agentSelectionView = AgentSuggestionBackgroundView(cornerRadius: 22)
    private let symbolView = IconView(size: 24, accessoryGeometry: .forIcon24)
    private let titleLabel = UILabel()
    private let selectedTitleView = UniversalSearchAgentTitleView()
    private var kind: Kind = .webSearch

    override init(frame: CGRect) {
        super.init(frame: frame)

        symbolView.imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .regular
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.applyTextStyle(.body)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        agentSelectionView.translatesAutoresizingMaskIntoConstraints = false
        agentSelectionView.isHidden = true
        agentSelectionView.isUserInteractionEnabled = false
        insertSubview(agentSelectionView, aboveSubview: highlightView)

        selectedTitleView.translatesAutoresizingMaskIntoConstraints = false
        selectedTitleView.isHidden = true

        contentView.addSubview(symbolView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(selectedTitleView)
        NSLayoutConstraint.activate([
            agentSelectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -16),
            agentSelectionView.topAnchor.constraint(equalTo: topAnchor),
            agentSelectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 16),
            agentSelectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 1),
            symbolView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectedTitleView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            selectedTitleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            selectedTitleView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectedTitleView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(kind: Kind, title: String) {
        self.kind = kind
        symbolView.config(with: UniversalSearchIconConfiguration(
            systemName: kind.systemName,
            foregroundColor: .label
        ))
        titleLabel.text = title
        selectedTitleView.configure(text: title)
        accessibilityLabel = title
        accessibilityTraits = .button
        refreshSelectionAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        kind = .webSearch
        refreshSelectionAppearance()
    }

    override func selectionAppearanceDidChange() {
        let showsAgentSelection = kind == .agent && isPresentedAsSelected
        agentSelectionView.isHidden = !showsAgentSelection
        titleLabel.isHidden = showsAgentSelection
        selectedTitleView.isHidden = !showsAgentSelection
        symbolView.imageView.tintColor = showsAgentSelection
            ? UIColor(cgColor: AgentSuggestionAppearance.titleGradientColors(for: traitCollection)[0])
            : .label
        accessibilityTraits = showsAgentSelection ? [.button, .selected] : .button
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        selectionAppearanceDidChange()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        selectionAppearanceDidChange()
    }
}

@MainActor
private final class UniversalSearchAgentTitleView: UIView {
    private let maskLabel = UILabel()
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        maskLabel.applyTextStyle(.body)
        maskLabel.textColor = .black
        maskLabel.lineBreakMode = .byTruncatingTail
        maskLabel.layer.contentsScale = UIScreen.main.scale

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.50749, 1]
        gradientLayer.mask = maskLabel.layer
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        updateGradientColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        maskLabel.intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLabel.frame = bounds
        maskLabel.layer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateGradientColors()
    }

    func configure(text: String) {
        maskLabel.text = text
        maskLabel.layer.setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    private func updateGradientColors() {
        AgentSuggestionAppearance.configureTitleGradient(gradientLayer, for: traitCollection)
    }
}

@MainActor
final class UniversalSearchPromptCell: UICollectionViewCell {
    static let height = AgentSuggestionButton.height
    private let suggestionButton = AgentSuggestionButton()

    override var isHighlighted: Bool {
        didSet { suggestionButton.isHighlighted = isHighlighted }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        suggestionButton.isUserInteractionEnabled = false
        suggestionButton.isAccessibilityElement = false
        suggestionButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(suggestionButton)
        NSLayoutConstraint.activate([
            suggestionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            suggestionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            suggestionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            suggestionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ prompt: UniversalSearchPrompt) {
        suggestionButton.configure(title: prompt.text)
        accessibilityLabel = prompt.text
        accessibilityTraits = .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        suggestionButton.resetPressedAppearance()
    }

    static func width(for text: String, maximumWidth: CGFloat) -> CGFloat {
        min(maximumWidth, AgentSuggestionButton.width(for: text))
    }
}
