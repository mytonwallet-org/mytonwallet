import ContextMenuKit
import UIComponents
import UIKit
import WalletContext
import WalletCore

private enum AgentFeedbackPillMetrics {
    static let bodyHeight: CGFloat = 56
    static let bodyPadding: CGFloat = 6
    static let buttonWidth: CGFloat = 48
    static let bodyWidth = bodyPadding * 2 + buttonWidth * 2
    static let iconPointSize: CGFloat = 30
    // The pill overlaps the answer's top edge and reaches past its trailing edge
    static let answerOverlap: CGFloat = 12
    static let answerOverhang: CGFloat = 20
    // The tail is a bump that grows out of the middle of the pill, half of it below the pill, and a dot below it
    // towards the answer's leading side
    static let bumpFrame = CGRect(x: bodyWidth / 2 - 8, y: bodyHeight - 8, width: 16, height: 16)
    static let dotFrame = CGRect(x: bodyWidth / 2 - 13, y: bodyHeight + 10, width: 8, height: 8)
    static let size = CGSize(width: bodyWidth, height: dotFrame.maxY)
    // The design's drop shadow: a 40 pt blur 8 pt down
    static let shadowRadius: CGFloat = 20
    static let shadowOffset = CGSize(width: 0, height: 8)
    static let shadowOpacity: Float = 0.12
    static let darkShadowOpacity: Float = 0.2
}

/// The like and dislike buttons that the menu of a complete answer shows over the answer
final class AgentFeedbackPillView: UIView {
    private static let options: [ApiAgentV2AnswerFeedback] = [.like, .dislike]

    /// Makes the menu accessory; `onSelect` gets the new rating, which is `nil` when the chosen one is pressed again
    static func makeMenuAccessory(
        feedback: ApiAgentV2AnswerFeedback?,
        onSelect: @escaping @MainActor (ApiAgentV2AnswerFeedback?) -> Void
    ) -> ContextMenuAccessory {
        ContextMenuAccessory(
            size: AgentFeedbackPillMetrics.size,
            topTrailingOffset: CGVector(
                dx: AgentFeedbackPillMetrics.answerOverhang,
                dy: AgentFeedbackPillMetrics.answerOverlap - AgentFeedbackPillMetrics.bodyHeight
            ),
            backgroundCapsules: [
                CGRect(
                    x: 0,
                    y: 0,
                    width: AgentFeedbackPillMetrics.bodyWidth,
                    height: AgentFeedbackPillMetrics.bodyHeight
                ),
                AgentFeedbackPillMetrics.bumpFrame,
                AgentFeedbackPillMetrics.dotFrame
            ],
            // The design's pill is near-white glass over the dimmed chat, lighter than the menu panel, with a soft
            // drop shadow around it
            glassTint: .strong,
            shadow: ContextMenuAccessoryShadow(
                lightOpacity: AgentFeedbackPillMetrics.shadowOpacity,
                darkOpacity: AgentFeedbackPillMetrics.darkShadowOpacity,
                radius: AgentFeedbackPillMetrics.shadowRadius,
                offset: AgentFeedbackPillMetrics.shadowOffset
            ),
            // The pill swells and stretches under the finger as the system's glass does
            isGlassInteractive: true
        ) { context in
            AgentFeedbackPillView(feedback: feedback) { selectedFeedback in
                onSelect(selectedFeedback)
                context.dismiss()
            }
        }
    }

    private let stackView = UIStackView()

    private init(
        feedback: ApiAgentV2AnswerFeedback?,
        onSelect: @escaping @MainActor (ApiAgentV2AnswerFeedback?) -> Void
    ) {
        super.init(frame: .zero)
        backgroundColor = .clear

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AgentFeedbackPillMetrics.bodyPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AgentFeedbackPillMetrics.bodyPadding),
            stackView.heightAnchor.constraint(equalToConstant: AgentFeedbackPillMetrics.bodyHeight)
        ])

        for option in Self.options {
            stackView.addArrangedSubview(makeButton(
                option: option,
                isSelected: option == feedback,
                onSelect: onSelect
            ))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(
        option: ApiAgentV2AnswerFeedback,
        isSelected: Bool,
        onSelect: @escaping @MainActor (ApiAgentV2AnswerFeedback?) -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: Self.symbolName(for: option))
        // The design's 30 pt glyph; a button would draw a symbol without a scale of its own at the large scale
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: AgentFeedbackPillMetrics.iconPointSize,
            weight: .regular,
            scale: .medium
        )
        // Both thumbs are filled in the design's vibrant primary label color; the chosen one takes the accent color
        configuration.baseForegroundColor = isSelected ? .tintColor : UIColor(light: "#333333", dark: "#FFFFFF")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
            Haptics.play(.lightTap)
            onSelect(isSelected ? nil : option)
        })
        button.accessibilityLabel = Self.accessibilityLabel(for: option)
        button.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        return button
    }

    private static func symbolName(for option: ApiAgentV2AnswerFeedback) -> String {
        switch option {
        case .like:
            "hand.thumbsup.fill"
        case .dislike:
            "hand.thumbsdown.fill"
        }
    }

    private static func accessibilityLabel(for option: ApiAgentV2AnswerFeedback) -> String {
        switch option {
        case .like:
            lang("Like")
        case .dislike:
            lang("Dislike")
        }
    }
}
