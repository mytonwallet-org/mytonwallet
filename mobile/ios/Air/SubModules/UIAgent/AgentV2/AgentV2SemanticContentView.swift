import UIKit
import WalletContext
import WalletCore

enum AgentV2MessagePresentation {
    struct Bubble: Equatable {
        let text: String
        let rendersMarkdown: Bool
    }

    static func bubble(for message: AgentV2NativeMessage) -> Bubble? {
        withMessageLanguage(message.responseLanguage) {
            if message.contentKind == .markdown {
                let text = message.text
                return text.isEmpty ? nil : Bubble(text: text, rendersMarkdown: true)
            }
            return nil
        }
    }

}

final class AgentV2SemanticContentView: UIView {
    enum Style {
        case card
        case embedded
    }

    private let stack = UIStackView()
    private let style: Style

    override init(frame: CGRect) {
        style = .card
        super.init(frame: frame)
        setupViews()
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setupViews()
    }

    private func setupViews() {
        let contentInset: CGFloat
        switch style {
        case .card:
            layer.cornerRadius = 20
            layer.cornerCurve = .continuous
            clipsToBounds = true
            contentInset = 16
        case .embedded:
            contentInset = 0
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInset),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: contentInset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInset)
        ])
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyTheme()
    }

    func configure(
        content: ApiAgentV2SemanticContent,
        responseLanguage: String?
    ) {
        resetContent()
        withMessageLanguage(responseLanguage) {
            switch content {
            case .notice(let notice): configureNotice(notice)
            case .clientUnsupported:
                stack.addArrangedSubview(makeLabel(lang("$agent_error_invalid_response"), style: .body))
            }
        }
    }

    func reset() {
        resetContent()
    }

    private func resetContent() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        accessibilityLabel = nil
    }

    private func configureNotice(_ notice: ApiAgentV2NoticeContent) {
        let text = AgentV2Copy.notice(notice)
        stack.addArrangedSubview(makeLabel(text, style: .body))
        accessibilityLabel = text
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func applyTheme() {
        switch style {
        case .card:
            backgroundColor = .air.secondaryFill
        case .embedded:
            backgroundColor = .clear
        }
    }

}
