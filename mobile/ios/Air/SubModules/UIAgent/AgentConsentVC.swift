import UIKit
import UIComponents
import WalletContext
import WalletCore

public enum AgentEntryPoint {
    @MainActor
    public static func makeRootViewController() -> UIViewController {
        AgentConsentStore.hasAccepted ? AgentVC() : AgentConsentVC()
    }

    public static func resetConsentStateForDebug() {
        AgentConsentStore.reset()
    }
}

private enum AgentConsentStore {
    private static let acceptedKey = "ui_agent.third_party_ai_consent.accepted"

    static var hasAccepted: Bool {
        UserDefaults.standard.bool(forKey: acceptedKey)
    }

    static func accept() {
        UserDefaults.standard.set(true, forKey: acceptedKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: acceptedKey)
    }
}

private enum AgentConsentMetrics {
    static let maxContentWidth: CGFloat = 580
    static let horizontalInset: CGFloat = 24
    static let topInset: CGFloat = -16
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
        lang("$agent_consent_feature_answers", arg1: APP_NAME)
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
        lang("$agent_consent_disclosure_text", arg1: APP_NAME)
    }
    static var allowButton: String {
        lang("$agent_consent_allow_button")
    }
    static var learnMore: String {
        lang("Learn more")
    }
}

private final class AgentConsentVC: WViewController {
    private let consentView = AgentConsentView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func scrollToTop(animated: Bool) {
        consentView.scrollToTop(animated: animated)
    }

    private func setupViews() {
        consentView.translatesAutoresizingMaskIntoConstraints = false
        consentView.onContinue = { [weak self] in
            self?.continueToAgent()
        }
        consentView.onLearnMore = {
            guard let url = URL(string: APP_PRIVACY_POLICY_URL) else { return }
            AppActions.openInBrowser(url, title: lang("Privacy Policy"), injectDappConnect: false)
        }

        view.addSubview(consentView)
        NSLayoutConstraint.activate([
            consentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            consentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consentView.topAnchor.constraint(equalTo: view.topAnchor),
            consentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        view.backgroundColor = .air.background
        addCustomNavigationBarBackground(color: .air.background)
    }

    private func continueToAgent() {
        AgentConsentStore.accept()
        let agentVC = AgentVC()
        guard let navigationController else {
            replaceWithEmbeddedAgent(agentVC)
            return
        }

        var viewControllers = navigationController.viewControllers
        if let index = viewControllers.firstIndex(of: self) {
            viewControllers[index] = agentVC
            navigationController.setViewControllers(viewControllers, animated: false)
        } else {
            navigationController.setViewControllers([agentVC], animated: false)
        }
    }

    private func replaceWithEmbeddedAgent(_ agentVC: AgentVC) {
        consentView.removeFromSuperview()
        addChild(agentVC)
        agentVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(agentVC.view)
        NSLayoutConstraint.activate([
            agentVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            agentVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            agentVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            agentVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        agentVC.didMove(toParent: self)
    }
}

private final class AgentConsentView: UIView {
    var onContinue: (() -> Void)?
    var onLearnMore: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let bottomContainerView = UIView()
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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
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
        bottomContainerView.backgroundColor = UIColor.air.background

        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(AgentConsentCopy.allowButton, for: .normal)
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
            scrollView.bottomAnchor.constraint(equalTo: bottomContainerView.topAnchor, constant: -200),

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
        contentStack.setCustomSpacing(6, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeLearnMoreButtonContainer())
    }

    private func makeHeaderView() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 14

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = AgentConsentMetrics.heroIconSize / 2
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: "sparkles"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .tintColor
        iconView.contentMode = .scaleAspectFit

        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: AgentConsentMetrics.heroIconSize),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
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

        container.addArrangedSubview(iconContainer)
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
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = AgentConsentCopy.disclosureTitle

        let bodyLabel = UILabel()
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .air.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.text = AgentConsentCopy.disclosureText

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    private func makeLearnMoreButtonContainer() -> UIView {
        let container = UIView()
        let button = makeLearnMoreButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        return container
    }

    private func makeLearnMoreButton() -> UIButton {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.image = UIImage(systemName: "chevron.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.title = AgentConsentCopy.learnMore
        configuration.baseForegroundColor = .tintColor
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: font, scale: .small)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = font
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: #selector(learnMoreButtonPressed), for: .touchUpInside)
        return button
    }

    @objc private func continueButtonPressed() {
        onContinue?()
    }

    @objc private func learnMoreButtonPressed() {
        onLearnMore?()
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
