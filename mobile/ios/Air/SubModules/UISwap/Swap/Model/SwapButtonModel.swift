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
                template: L10n.swapFromTo(
                    from: "{{from}}",
                    icon: "{{icon}}",
                    to: "{{to}}"
                ),
                sellingSymbol: sellingToken.symbol,
                buyingSymbol: buyingToken.symbol
            )
        case .continue:
            .text(lang("Continue"))
        case .authorizeDiesel(let token):
            .text(L10n.authorizeTokenFeeCapitalized(token: token.symbol))
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
    let delaysDisabledAppearance: Bool
    private let presentationIdentity: SwapButtonPresentationIdentity

    init(
        title: SwapButtonTitle,
        isEnabled: Bool,
        showLoading: Bool,
        delaysDisabledAppearance: Bool = false
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.showLoading = showLoading
        self.delaysDisabledAppearance = delaysDisabledAppearance
        self.presentationIdentity = title.presentationIdentity
    }

    func hasSamePresentation(as other: SwapButtonConfiguration) -> Bool {
        presentationIdentity == other.presentationIdentity
            && isEnabled == other.isEnabled
            && showLoading == other.showLoading
            && delaysDisabledAppearance == other.delaysDisabledAppearance
    }

    @MainActor func applyContent(to button: WButton) {
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
        button.showLoading = showLoading
    }
}

@MainActor
final class SwapButtonPresentationController {
    typealias DisabledAppearanceScheduler = (
        _ update: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>

    private let button: WButton
    private let scheduleDisabledAppearance: DisabledAppearanceScheduler
    private var configuration: SwapButtonConfiguration?
    private var disabledAppearanceTask: Task<Void, Never>?

    init(
        button: WButton,
        disabledAppearanceDelay: Duration = .seconds(1)
    ) {
        self.button = button
        self.scheduleDisabledAppearance = { update in
            Task { @MainActor in
                try? await Task.sleep(for: disabledAppearanceDelay)
                guard !Task.isCancelled else { return }
                update()
            }
        }
    }

    init(
        button: WButton,
        scheduleDisabledAppearance: @escaping DisabledAppearanceScheduler
    ) {
        self.button = button
        self.scheduleDisabledAppearance = scheduleDisabledAppearance
    }

    deinit {
        disabledAppearanceTask?.cancel()
    }

    func apply(_ configuration: SwapButtonConfiguration) {
        guard self.configuration?.hasSamePresentation(as: configuration) != true else {
            return
        }
        self.configuration = configuration
        configuration.applyContent(to: button)

        // Interaction follows the real draft state even while the disabled appearance is delayed.
        button.isUserInteractionEnabled = configuration.isEnabled
        if configuration.isEnabled {
            cancelDelayedDisable()
            button.isEnabled = true
        } else if disabledAppearanceTask != nil {
            // Keep the original invalidation deadline while applying newer loading/error content.
        } else if button.isEnabled, configuration.delaysDisabledAppearance {
            scheduleDelayedDisable()
        } else {
            button.isEnabled = false
        }
    }

    private func scheduleDelayedDisable() {
        disabledAppearanceTask = scheduleDisabledAppearance { [weak self] in
            guard let self, self.configuration?.isEnabled == false else {
                return
            }
            self.button.isEnabled = false
            self.disabledAppearanceTask = nil
        }
    }

    private func cancelDelayedDisable() {
        disabledAppearanceTask?.cancel()
        disabledAppearanceTask = nil
    }
}

@MainActor final class SwapButtonModel {
    func configuration(for state: SwapButtonState, sellingToken: ApiToken?, buyingToken: ApiToken?) -> SwapButtonConfiguration {
        guard let sellingToken, let buyingToken else {
            return SwapButtonConfiguration(title: .continue, isEnabled: false, showLoading: false)
        }
        switch state {
        case .invalidPair:
            return SwapButtonConfiguration(
                title: .issue(.invalidPair),
                isEnabled: false,
                showLoading: false,
                delaysDisabledAppearance: true
            )
        case .emptyAmount, .waitingForEstimate:
            return SwapButtonConfiguration(
                title: .swap(sellingToken, buyingToken),
                isEnabled: false,
                showLoading: false,
                delaysDisabledAppearance: true
            )
        case .estimating(let showContinue):
            let title: SwapButtonTitle = showContinue ? .continue : .swap(sellingToken, buyingToken)
            return SwapButtonConfiguration(
                title: title,
                isEnabled: false,
                showLoading: true,
                delaysDisabledAppearance: true
            )
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
    func configureTitle(sellingToken: ApiToken?, buyingToken: ApiToken?) {
        guard let sellingToken, let buyingToken else {
            configureTitleContinue()
            return
        }
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
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitleContinue() {
        let attr = NSMutableAttributedString(string: lang("Continue"))
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitleAuthorizeDiesel(sellingToken: ApiToken) {
        let attr = NSMutableAttributedString(string: L10n.authorizeTokenFeeCapitalized(token: sellingToken.symbol))
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
    
    func configureTitle(issue: SwapIssue) {
        let attr = NSMutableAttributedString(string: issue.buttonTitle)
        attr.addAttribute(.font, value: WButton.font, range: NSRange(location: 0, length: attr.length))
        setAttributedTitle(attr, for: .normal)
    }
}

private extension String {
    var leftToRightIsolated: String {
        "\u{2066}\(self)\u{2069}"
    }
}
