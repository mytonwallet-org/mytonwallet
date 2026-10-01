import UIKit

public struct DraftButtonConfiguration: Equatable {
    public enum Title {
        case text(String)
        /// Compared by `identity`, so styling details that do not change
        /// the rendered text do not count as a presentation change.
        case attributed(NSAttributedString, identity: String)
    }

    public let title: Title
    public let isEnabled: Bool
    public let showLoading: Bool

    public init(
        title: Title,
        isEnabled: Bool,
        showLoading: Bool
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.showLoading = showLoading
    }
}

extension DraftButtonConfiguration.Title: Equatable {
    public static func == (
        lhs: DraftButtonConfiguration.Title,
        rhs: DraftButtonConfiguration.Title
    ) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhs), .text(let rhs)):
            lhs == rhs
        case (.attributed(_, let lhs), .attributed(_, let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}

/// Keeps a previously enabled appearance while a plausible replacement draft
/// loads. Interaction and accessibility always follow the actual readiness;
/// a definitive disabled state takes effect immediately. There is no timeout.
@MainActor
public final class DraftButtonPresenter {
    private let button: WButton
    private var configuration: DraftButtonConfiguration?
    private var appearsEnabled = false

    public init(button: WButton) {
        self.button = button
    }

    public func apply(_ configuration: DraftButtonConfiguration) {
        if self.configuration != configuration {
            self.configuration = configuration
            applyContent(configuration)
        }
        if configuration.isEnabled || !configuration.showLoading {
            appearsEnabled = configuration.isEnabled
        }
        button.isEnabled = appearsEnabled
        button.isUserInteractionEnabled = configuration.isEnabled
        if configuration.isEnabled {
            button.accessibilityTraits.remove(.notEnabled)
        } else {
            button.accessibilityTraits.insert(.notEnabled)
        }
    }

    private func applyContent(_ configuration: DraftButtonConfiguration) {
        switch configuration.title {
        case .text(let title):
            if button.attributedTitle(for: .normal) != nil {
                button.setAttributedTitle(nil, for: .normal)
            }
            if button.title(for: .normal) != title {
                button.setTitle(title, for: .normal)
            }
        case .attributed(let title, _):
            button.setAttributedTitle(title, for: .normal)
        }
        button.showLoading = configuration.showLoading
    }
}
