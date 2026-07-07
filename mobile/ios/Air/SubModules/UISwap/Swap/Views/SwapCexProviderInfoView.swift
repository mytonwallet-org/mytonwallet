import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct SwapCexProviderInfoView: View {
    let providerName: String
    let termsOfUseUrl: String?
    let privacyPolicyUrl: String?
    let amlKycPolicyUrl: String?
    
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
                            AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
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
        Text(lang("Cross-chain exchange provided by %provider%", arg1: providerName))
            .foregroundStyle(Color.air.secondaryLabel)
    }
    
    @ViewBuilder
    var text: some View {
        if let legalDisclaimer {
            Text(LocalizedStringKey(legalDisclaimer))
                .lineSpacing(3)
                .foregroundStyle(Color.air.secondaryLabel)
                .font(.footnote)
                .padding(.top, 2)
        }
    }

    private var legalDisclaimer: String? {
        let terms = markdownLink(text: lang("$swap_cex_terms_of_use"), url: termsOfUseUrl)
        let policy = markdownLink(text: lang("$swap_cex_privacy_policy"), url: privacyPolicyUrl)
        let aml = markdownLink(text: lang("$swap_cex_aml_kyc_policy"), url: amlKycPolicyUrl)

        guard terms != nil || policy != nil || aml != nil else {
            return nil
        }

        if let terms, let policy, let aml {
            return lang("$swap_cex_legal_message_with_aml",
                arg1: terms,
                arg2: policy,
                arg3: aml
            )
        }

        if let terms, let policy {
            return lang("$swap_cex_legal_message", arg1: terms, arg2: policy)
        }

        return langJoin([terms, policy, aml].compactMap { $0 }, .and)
    }

    private func markdownLink(text: String, url rawUrl: String?) -> String? {
        guard let url = URL.sanitizedHttpUrl(from: rawUrl) else {
            return nil
        }
        return "[\(text)](\(url.absoluteString))"
    }
}
