import SwiftUI
import WalletContext
import WalletCore

public struct MultisigWalletWarning: View {
    public init() {}

    private var helpUrl: URL {
        let urlString = Language.current == .ru ? HELP_CENTER_SEED_SCAM_URL_RU : HELP_CENTER_SEED_SCAM_URL
        return URL(string: urlString)!
    }

    public var body: some View {
        WarningView(
            header: lang("Multisig Wallet Detected"),
            text: L10n.multisigWarningText(appName: APP_NAME, multisigWarningLink: "[\(lang("$multisig_warning_link"))](\(helpUrl.absoluteString))"),
            kind: .error
        )
        .environment(\.openURL, OpenURLAction { url in
            topViewController()?.view.endEditing(true)
            AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
            return .handled
        })
    }
}

#Preview {
    MultisigWalletWarning()
}
