import UIKit
import UIComponents
import WalletContext
import WalletCore

enum SwapButtonTitle {
    case swap(ApiToken, ApiToken)
    case `continue`
    case authorizeDiesel(ApiToken)
    case invalidPair
    case error(String)
}

struct SwapButtonConfiguration {
    let title: SwapButtonTitle
    let isEnabled: Bool
    let showLoading: Bool

    func apply(to button: WButton) {
        switch title {
        case .swap(let sellingToken, let buyingToken):
            button.configureTitle(sellingToken: sellingToken, buyingToken: buyingToken)
        case .continue:
            button.configureTitleContinue()
        case .authorizeDiesel(let token):
            button.configureTitleAuthorizeDiesel(sellingToken: token)
        case .invalidPair:
            button.configureTitleInvalidPair()
        case .error(let message):
            button.configureTitle(swapError: message)
        }
        button.isEnabled = isEnabled
        button.showLoading = showLoading
    }
}

@MainActor final class SwapButtonModel {
    func configurationForEmptyAmounts(isValidPair: Bool, sellingToken: ApiToken, buyingToken: ApiToken) -> SwapButtonConfiguration {
        if !isValidPair {
            return SwapButtonConfiguration(title: .invalidPair, isEnabled: false, showLoading: false)
        }
        return SwapButtonConfiguration(title: .swap(sellingToken, buyingToken), isEnabled: false, showLoading: false)
    }

    func configurationForOnchain(isValidPair: Bool, swapEstimate: ApiSwapEstimateResponse?, lateInit: ApiSwapCexEstimateResponse.LateInitProperties?, swapError: String?, shouldShowContinue: Bool, sellingToken: ApiToken, buyingToken: ApiToken) -> SwapButtonConfiguration? {
        if !isValidPair {
            return SwapButtonConfiguration(title: .invalidPair, isEnabled: false, showLoading: false)
        }
        if let swapError {
            return SwapButtonConfiguration(title: .error(swapError), isEnabled: false, showLoading: false)
        }
        guard let swapEstimate, let lateInit else {
            return nil
        }
        if lateInit.isDiesel == true, swapEstimate.dieselStatus == .notAuthorized {
            return SwapButtonConfiguration(title: .authorizeDiesel(sellingToken), isEnabled: true, showLoading: false)
        }
        if shouldShowContinue {
            return SwapButtonConfiguration(title: .continue, isEnabled: true, showLoading: false)
        }
        return SwapButtonConfiguration(title: .swap(sellingToken, buyingToken), isEnabled: true, showLoading: false)
    }

    func configurationForCrosschain(isValidPair: Bool, swapEstimate: ApiSwapCexEstimateResponse?, swapError: String?, shouldShowContinue: Bool, sellingToken: ApiToken, buyingToken: ApiToken) -> SwapButtonConfiguration? {
        if !isValidPair {
            return SwapButtonConfiguration(title: .invalidPair, isEnabled: false, showLoading: false)
        }
        guard let swapEstimate else {
            return nil
        }
        if let swapError {
            return SwapButtonConfiguration(title: .error(swapError), isEnabled: false, showLoading: false)
        }
        if swapEstimate.isDiesel == true, swapEstimate.dieselStatus == .notAuthorized {
            return SwapButtonConfiguration(title: .authorizeDiesel(sellingToken), isEnabled: true, showLoading: false)
        }
        if shouldShowContinue {
            return SwapButtonConfiguration(title: .continue, isEnabled: true, showLoading: false)
        }
        return SwapButtonConfiguration(title: .swap(sellingToken, buyingToken), isEnabled: true, showLoading: false)
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
            let image = UIImage(systemName: "chevron.forward", withConfiguration: config)!
            let attachment = NSTextAttachment(image: image)
            attr.append(NSAttributedString(attachment: attachment))
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
    
    func configureTitleInvalidPair() {
        let attr = NSMutableAttributedString(string: lang("Invalid Pair"))
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitle(swapError: String) {
        let attr = NSMutableAttributedString(string: swapError)
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
}
