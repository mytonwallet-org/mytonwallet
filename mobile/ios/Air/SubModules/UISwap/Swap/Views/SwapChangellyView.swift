
import Combine
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


struct SwapChangellyView: View {
    
    var body: some View {
        InsetSection {
            InsetCell {
                VStack(alignment: .leading, spacing: 7) {
                    header
                        .padding(.top, 1)
                    text
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 1)
                        .environment(\.openURL, OpenURLAction { url in
                            topViewController()?.view.endEditing(true)
                            AppActions.openInBrowser(url, title: nil, injectTonConnect: false)
                            return .handled
                        })
                }
            }
        } header: {} footer: {}
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, -16)
    }
    
    var header: some View {
        HStack(spacing: 0) {
            Text(lang("Cross-chain swap by %1$@", arg1: ""))
            Image("SwapChangellyLogo", bundle: AirBundle)
        }
        .foregroundStyle(Color(WTheme.secondaryLabel))
    }
    
    var text: some View {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let disclaimer = lang("$swap_changelly_agreement_message",
            arg1: "[\(lang("$swap_changelly_terms_of_use"))](https://changelly.com/terms-of-use)",
            arg2: "[\(lang("$swap_changelly_privacy_policy"))](https://changelly.com/privacy-policy)",
            arg3: "[\(lang("Changelly AML/KYC"))](https://changelly.com/aml-kyc)"
        )
        return Text(LocalizedStringKey(disclaimer))
            .lineSpacing(3)
            .foregroundStyle(Color(WTheme.secondaryLabel))
            .font(.footnote)
            .padding(.top, 2)
    }
}
