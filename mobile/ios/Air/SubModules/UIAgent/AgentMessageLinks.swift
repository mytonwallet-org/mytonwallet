import Foundation
import UIKit
import WalletContext
import WalletCore

private let log = Log("AgentVC")

enum AgentMessageLinks {
    @MainActor
    static func openMessageURL(
        _ url: URL,
        renderingPolicy: AgentMessageRenderingPolicy,
        handleDeeplink: (URL) -> Bool = { WalletContextManager.delegate?.handleDeeplink(url: $0) ?? false },
        openTelegram: (URL) -> Void = { UIApplication.shared.open($0, options: [:], completionHandler: nil) },
        openBrowser: (URL) -> Void = { AppActions.openInBrowser($0, title: nil, injectDappConnect: false) },
        showError: (DisplayError) -> Void = { AppActions.showError(error: $0) }
    ) {
        if renderingPolicy == .agentV2Safe {
            guard AgentTextLinks.isOpenable(url) else {
                log.error("unsupported agent answer url=\(url.absoluteString, .public)")
                showError(DisplayError(text: lang("Unsupported link")))
                return
            }
            if AgentTextLinks.isAppScreenLink(url) {
                if !handleDeeplink(url) {
                    log.error("unhandled agent answer deeplink url=\(url.absoluteString, .public)")
                    showError(DisplayError(text: lang("Unsupported link")))
                }
            } else if url.isTelegramURL {
                openTelegram(url)
            } else {
                openBrowser(url)
            }
            return
        }

        guard !handleDeeplink(url) else { return }
        if url.isTelegramURL {
            openTelegram(url)
        } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            openBrowser(url)
        } else {
            log.error("unsupported agent url=\(url.absoluteString, .public)")
            showError(DisplayError(text: lang("Unsupported link")))
        }
    }
}
