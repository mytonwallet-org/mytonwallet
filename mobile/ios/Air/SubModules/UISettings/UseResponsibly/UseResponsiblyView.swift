//
//  AboutView.swift
//  UICreateWallet
//
//  Created by nikstar on 05.09.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext

struct UseResponsiblyView: View {

    var body: some View {
        InsetList(topPadding: 0) {
            header
            longDescription
            links
                .padding(.bottom, 32)
        }
        .backportScrollBounceBehaviorBasedOnSize()
    }
    
    @ViewBuilder
    var header: some View {
        VStack(spacing: 24) {
            WUIAnimatedSticker("animation_snitch", size: 96, loop: false)
                .frame(width: 96, height: 96)
            Text(lang("Use Responsibly"))
                .font(.system(size: 28, weight: .semibold))
        }
        .environment(\.openURL, OpenURLAction { url in
            UIApplication.shared.open(url)
            return .handled
        })
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    var longDescription: some View {
        let text = [
            lang("$auth_responsibly_description1", arg1: APP_NAME),
            lang("$auth_responsibly_description2"),
            lang("$auth_responsibly_description3", arg1: APP_NAME),
            lang("$auth_responsibly_description4"),
        ].joined(separator: "\n\n")
        InsetSection {
            InsetCell {
                Text(LocalizedStringKey(text))
            }
        }
    }
    
    var links: some View {
        InsetSection(dividersInset: 46) {
            Item(
                icon: "TermsIcon",
                text: lang("Terms of Use"),
                onTap: onTerms
            )
            Item(
                icon: "PolicyIcon",
                text: lang("Privacy Policy"),
                onTap: onPrivacyPolicy
            )
        }
    }
    
    func onTerms() {
        open("https://mytonwallet.io/terms-of-use")
    }
    
    func onPrivacyPolicy() {
        open("https://mytonwallet.io/privacy-policy")
    }
    
    func open(_ string: String) {
        let url = URL(string: string)!
        UIApplication.shared.open(url)
    }
}


private struct Item: View {
    
    var icon: String
    var text: String
    var onTap: () -> ()
    
    var body: some View {
        InsetButtonCell(verticalPadding: 8, action: onTap) {
            HStack(spacing: 16) {
                Image.airBundle(icon)
                    .clipShape(.rect(cornerRadius: 8))
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image.airBundle("RightArrowIcon")
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .backportGeometryGroup()
        }
    }
}
