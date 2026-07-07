import UIKit
import UIComponents
import WalletContext
import WalletCore

enum SwapButtonTitle {
    case swap(ApiToken, ApiToken)
    case `continue`
    case authorizeDiesel(ApiToken)
    case issue(SwapIssue)
}

private enum SwapButtonPresentationIdentity: Equatable {
    case swap(template: String, sellingSymbol: String, buyingSymbol: String)
    case text(String)
}

extension SwapButtonTitle {
    fileprivate var presentationIdentity: SwapButtonPresentationIdentity {
        switch self {
        case .swap(let sellingToken, let buyingToken):
            .swap(
                template: lang("$swap_from_to"),
                sellingSymbol: sellingToken.symbol,
                buyingSymbol: buyingToken.symbol
            )
        case .continue:
            .text(lang("Continue"))
        case .authorizeDiesel(let token):
            .text(lang("Authorize %token% Fee", arg1: token.symbol))
        case .issue(let issue):
            .text(issue.buttonTitle)
        }
    }
}

enum SwapButtonState: Equatable {
    case invalidPair
    case emptyAmount
    case estimating(showContinue: Bool)
    case waitingForEstimate
    case blocked(SwapIssue)
    case authorizeDiesel
    case readyToContinue
    case readyToSwap
}

struct SwapButtonConfiguration {
    let title: SwapButtonTitle
    let isEnabled: Bool
    let showLoading: Bool
    private let presentationIdentity: SwapButtonPresentationIdentity

    init(title: SwapButtonTitle, isEnabled: Bool, showLoading: Bool) {
        self.title = title
        self.isEnabled = isEnabled
        self.showLoading = showLoading
        self.presentationIdentity = title.presentationIdentity
    }

    func hasSamePresentation(as other: SwapButtonConfiguration) -> Bool {
        presentationIdentity == other.presentationIdentity
            && isEnabled == other.isEnabled
            && showLoading == other.showLoading
    }

    @MainActor func apply(to button: WButton) {
        switch title {
        case .swap(let sellingToken, let buyingToken):
            button.configureTitle(sellingToken: sellingToken, buyingToken: buyingToken)
        case .continue:
            button.configureTitleContinue()
        case .authorizeDiesel(let token):
            button.configureTitleAuthorizeDiesel(sellingToken: token)
        case .issue(let issue):
            button.configureTitle(issue: issue)
        }
        button.isEnabled = isEnabled
        button.showLoading = showLoading
    }
}

@MainActor final class SwapButtonModel {
    func configuration(for state: SwapButtonState, sellingToken: ApiToken, buyingToken: ApiToken) -> SwapButtonConfiguration {
        switch state {
        case .invalidPair:
            return SwapButtonConfiguration(title: .issue(.invalidPair), isEnabled: false, showLoading: false)
        case .emptyAmount, .waitingForEstimate:
            return SwapButtonConfiguration(title: .swap(sellingToken, buyingToken), isEnabled: false, showLoading: false)
        case .estimating(let showContinue):
            let title: SwapButtonTitle = showContinue ? .continue : .swap(sellingToken, buyingToken)
            return SwapButtonConfiguration(title: title, isEnabled: false, showLoading: true)
        case .blocked(let issue):
            return SwapButtonConfiguration(title: .issue(issue), isEnabled: false, showLoading: false)
        case .authorizeDiesel:
            return SwapButtonConfiguration(title: .authorizeDiesel(sellingToken), isEnabled: true, showLoading: false)
        case .readyToContinue:
            return SwapButtonConfiguration(title: .continue, isEnabled: true, showLoading: false)
        case .readyToSwap:
            return SwapButtonConfiguration(title: .swap(sellingToken, buyingToken), isEnabled: true, showLoading: false)
        }
    }
}

extension WButton {
    func configureTitle(sellingToken: ApiToken, buyingToken: ApiToken) {
        let containsChevron = lang("$swap_from_to").contains("%3$@")
        if containsChevron {
            let s = lang("$swap_from_to", arg1: sellingToken.symbol, arg2: "{{chevron}}", arg3: buyingToken.symbol)
            let a = s.split(separator: "{{chevron}}")
            guard a.count >= 2 else { return }
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: String(a[0])))
            let config = UIImage.SymbolConfiguration(font: WButton.font, scale: .small)
            if let image = UIImage(systemName: "chevron.forward", withConfiguration: config) {
                let attachment = NSTextAttachment(image: image)
                attr.append(NSAttributedString(attachment: attachment))
            }
            attr.append(NSAttributedString(string: String(a[1])))
            attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
            setAttributedTitle(attr, for: .normal)
        } else {
            let s = lang("$swap_from_to", arg1: sellingToken.symbol, arg2: buyingToken.symbol)
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: s))
            attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
            setAttributedTitle(attr, for: .normal)
        }
    }
    
    func configureTitleContinue() {
        let attr = NSMutableAttributedString(string: lang("Continue"))
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitleAuthorizeDiesel(sellingToken: ApiToken) {
        let attr = NSMutableAttributedString(string: lang("Authorize %token% Fee", arg1: sellingToken.symbol))
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitle(issue: SwapIssue) {
        let attr = NSMutableAttributedString(string: issue.buttonTitle)
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
}
