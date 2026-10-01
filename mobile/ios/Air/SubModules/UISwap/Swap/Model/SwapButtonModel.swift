import UIKit
import UIComponents
import WalletContext
import WalletCore

enum SwapButtonState: Equatable {
    case submitting
    case invalidPair
    case emptyAmount
    case estimating(showContinue: Bool)
    case waitingForEstimate
    case blocked(SwapIssue)
    case authorizeDiesel
    case readyToContinue
    case readyToSwap
}

@MainActor final class SwapButtonModel {
    func configuration(for state: SwapButtonState, sellingToken: ApiToken?, buyingToken: ApiToken?) -> DraftButtonConfiguration {
        guard let sellingToken, let buyingToken else {
            return .init(title: .text(lang("Continue")), isEnabled: false, showLoading: false)
        }
        let swapTitle = swapTitle(sellingToken: sellingToken, buyingToken: buyingToken)
        switch state {
        case .submitting:
            return .init(title: swapTitle, isEnabled: false, showLoading: true)
        case .invalidPair:
            return .init(title: .text(SwapIssue.invalidPair.buttonTitle), isEnabled: false, showLoading: false)
        case .emptyAmount, .waitingForEstimate:
            return .init(title: swapTitle, isEnabled: false, showLoading: false)
        case .estimating(let showContinue):
            return .init(title: showContinue ? .text(lang("Continue")) : swapTitle, isEnabled: false, showLoading: true)
        case .blocked(let issue):
            return .init(title: .text(issue.buttonTitle), isEnabled: false, showLoading: false)
        case .authorizeDiesel:
            return .init(title: .text(L10n.authorizeTokenFeeCapitalized(token: sellingToken.symbol)), isEnabled: true, showLoading: false)
        case .readyToContinue:
            return .init(title: .text(lang("Continue")), isEnabled: true, showLoading: false)
        case .readyToSwap:
            return .init(title: swapTitle, isEnabled: true, showLoading: false)
        }
    }

    private func swapTitle(sellingToken: ApiToken, buyingToken: ApiToken) -> DraftButtonConfiguration.Title {
        let sellingSymbol = sellingToken.symbol.leftToRightIsolated
        let buyingSymbol = buyingToken.symbol.leftToRightIsolated
        let chevronPlaceholder = "{{chevron}}"
        let title = L10n.swapFromTo(from: sellingSymbol, icon: chevronPlaceholder, to: buyingSymbol)
        let components = title.components(separatedBy: chevronPlaceholder)
        let attr = NSMutableAttributedString()

        if components.count == 2 {
            attr.append(NSAttributedString(string: components[0]))
            let config = UIImage.SymbolConfiguration(font: WButton.font, scale: .small)
            if let image = UIImage(systemName: "chevron.forward", withConfiguration: config) {
                let attachment = NSTextAttachment(image: image)
                attr.append(NSAttributedString(attachment: attachment))
            }
            attr.append(NSAttributedString(string: components[1]))
        } else {
            attr.append(NSAttributedString(string: title))
        }
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        return .attributed(attr, identity: attr.string)
    }
}

private extension String {
    var leftToRightIsolated: String {
        "\u{2066}\(self)\u{2069}"
    }
}
