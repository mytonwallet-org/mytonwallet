import UIKit
import UIComponents
import WalletContext
import WalletCore

private enum AgentConsentMetrics {
    static let maxContentWidth: CGFloat = 580
    static let horizontalInset: CGFloat = 24
    static let topInset: CGFloat = 24
    static let bottomInset: CGFloat = 24
    static let buttonHorizontalInset: CGFloat = 16
    static let rowIconSize: CGFloat = 32
    static let heroIconSize: CGFloat = 74
    static let disclosureCornerRadius: CGFloat = 18
}

private enum AgentConsentCopy {
    static var subtitle: String {
        lang("$agent_consent_subtitle")
    }
    static var rowOne: String {
        L10n.agentConsentFeatureAnswers(appName: APP_NAME)
    }
    static var rowTwo: String {
        lang("$agent_consent_feature_actions")
    }
    static var rowThree: String {
        lang("$agent_consent_feature_context")
    }
    static var disclosureTitle: String {
        lang("Data shared with Agent")
    }
    static var disclosureText: String {
        L10n.agentConsentDisclosureText(appName: APP_NAME)
    }
    static var allowButton: String {
        lang("$agent_consent_allow_button")
    }
    static var learnMore: String {
        lang("Learn more")
    }
}

final class AgentConsentView: UIView {
    var onContinue: (() -> Void)?
    var onLearnMore: (() -> Void)?
    var isActive = true {
        didSet { iconView.isActive = isActive }
    }

    private let iconView = AgentSpinningTopView(speedMultiplier: 0.5, expandedScale: 2, centersExpandedTop: true)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let disclosureTextView = UITextView()
    private let bottomContainerView = UIView()
    private let bottomFade = CAGradientLayer()
    private let continueButton = WButton(style: .primary)
    private let contentWidthGuide = UILayoutGuide()
    private let buttonWidthGuide = UILayoutGuide()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func scrollToTop(animated: Bool) {
        let offset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        scrollView.setContentOffset(offset, animated: animated)
    }

    private func setupViews() {
        backgroundColor = UIColor.air.background

        iconView.backdropSourceView = scrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = UIColor.air.background
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.isHidden = true
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill

        bottomContainerView.translatesAutoresizingMaskIntoConstraints = false
        bottomContainerView.layer.insertSublayer(bottomFade, at: 0)

        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(AgentConsentCopy.allowButton, for: .normal)
        continueButton.accessibilityIdentifier = "agent_consent_allow"
        continueButton.addTarget(self, action: #selector(continueButtonPressed), for: .touchUpInside)

        addLayoutGuide(contentWidthGuide)
        addLayoutGuide(buttonWidthGuide)
        addSubview(scrollView)
        addSubview(bottomContainerView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)
        bottomContainerView.addSubview(continueButton)

        buildContent()

        let contentFullWidthConstraint = contentWidthGuide.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor)
        contentFullWidthConstraint.priority = UILayoutPriority(999)
        let buttonFullWidthConstraint = buttonWidthGuide.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor)
        buttonFullWidthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            contentWidthGuide.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            contentWidthGuide.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor),
            contentWidthGuide.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor),
            contentFullWidthConstraint,
            contentWidthGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentConsentMetrics.maxContentWidth),

            buttonWidthGuide.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            buttonWidthGuide.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor),
            buttonWidthGuide.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor),
            buttonFullWidthConstraint,
            buttonWidthGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentConsentMetrics.maxContentWidth),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentWidthGuide.leadingAnchor, constant: AgentConsentMetrics.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: contentWidthGuide.trailingAnchor, constant: -AgentConsentMetrics.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AgentConsentMetrics.topInset),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AgentConsentMetrics.bottomInset),

            bottomContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            continueButton.leadingAnchor.constraint(equalTo: buttonWidthGuide.leadingAnchor, constant: AgentConsentMetrics.buttonHorizontalInset),
            continueButton.trailingAnchor.constraint(equalTo: buttonWidthGuide.trailingAnchor, constant: -AgentConsentMetrics.buttonHorizontalInset),
            continueButton.topAnchor.constraint(equalTo: bottomContainerView.topAnchor, constant: 12),
            continueButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bottomFade.frame = bottomContainerView.bounds
        bottomFade.colors = [
            UIColor.air.background.withAlphaComponent(0).cgColor,
            UIColor.air.background.cgColor,
        ]
        bottomFade.locations = [0, 0.35]
        scrollView.contentInset.bottom = max(0, bottomContainerView.bounds.height - safeAreaInsets.bottom)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        disclosureTextView.linkTextAttributes = AgentMessageTextRenderer.linkTextAttributes(color: tintColor)
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeHeaderView())
        contentStack.setCustomSpacing(34, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makeInfoRow(iconName: "questionmark.bubble.fill", text: AgentConsentCopy.rowOne))
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeInfoRow(iconName: "wand.and.sparkles", text: AgentConsentCopy.rowTwo))
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeInfoRow(iconName: "wallet.pass.fill", text: AgentConsentCopy.rowThree))
        contentStack.setCustomSpacing(28, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makeDisclosureView())
    }

    private func makeHeaderView() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 14

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: AgentConsentMetrics.heroIconSize),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(.bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.text = lang("Agent")

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .air.secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = AgentConsentCopy.subtitle

        container.addArrangedSubview(iconView)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(subtitleLabel)
        return container
    }

    private func makeInfoRow(iconName: String, text: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor.air.secondaryFill
        iconContainer.layer.cornerRadius = 10
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .tintColor
        iconView.contentMode = .scaleAspectFit

        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: AgentConsentMetrics.rowIconSize),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])

        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text

        row.addArrangedSubview(iconContainer)
        row.addArrangedSubview(label)
        return row
    }

    private func makeDisclosureView() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.air.groupedItem
        container.layer.cornerRadius = AgentConsentMetrics.disclosureCornerRadius
        container.layer.cornerCurve = .continuous

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = AgentConsentCopy.disclosureTitle
        titleLabel.accessibilityIdentifier = "agent_consent_title"

        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let disclosure = NSMutableAttributedString(
            string: AgentConsentCopy.disclosureText + " ",
            attributes: [.font: font, .foregroundColor: UIColor.air.secondaryLabel]
        )
        disclosure.append(NSAttributedString(
            string: AgentConsentCopy.learnMore,
            attributes: [.font: font, .link: APP_PRIVACY_POLICY_URL]
        ))
        disclosureTextView.backgroundColor = .clear
        disclosureTextView.isEditable = false
        disclosureTextView.isScrollEnabled = false
        disclosureTextView.isSelectable = true
        disclosureTextView.textContainerInset = .zero
        disclosureTextView.textContainer.lineFragmentPadding = 0
        disclosureTextView.textContainer.lineBreakMode = .byWordWrapping
        disclosureTextView.textDragInteraction?.isEnabled = false
        disclosureTextView.font = font
        disclosureTextView.adjustsFontForContentSizeCategory = true
        disclosureTextView.attributedText = disclosure
        disclosureTextView.linkTextAttributes = AgentMessageTextRenderer.linkTextAttributes(color: tintColor)
        disclosureTextView.delegate = self
        disclosureTextView.accessibilityIdentifier = "agent_consent_learn_more"
        disclosureTextView.setContentHuggingPriority(UILayoutPriority(999), for: .vertical)
        disclosureTextView.setContentCompressionResistancePriority(UILayoutPriority(999), for: .vertical)
        disclosureTextView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(disclosureTextView)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    @objc private func continueButtonPressed() {
        onContinue?()
    }
}

extension AgentConsentView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard interaction == .invokeDefaultAction else { return false }
        onLearnMore?()
        return false
    }
}

private extension UIFont {
    func withWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
