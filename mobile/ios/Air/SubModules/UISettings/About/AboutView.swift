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
import WalletCore

struct AboutView: View {
    
    var showLegalSection: Bool
    
    var body: some View {
        InsetList(topPadding: 0) {
            header
            longDescription
            resources
                .padding(.bottom, showLegalSection ? 0 : 32)
            if showLegalSection {
                legal
            }
        }
        .backportScrollBounceBehaviorBasedOnSize()
    }
    
    @ViewBuilder
    var header: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let websiteUrl = URL(string: APP_WEBSITE_URL)!
        let websiteTitle = websiteUrl.host ?? APP_WEBSITE_URL
        VStack(spacing: 14) {
            Image.airBundle(IS_GRAM_WALLET ? "IntroLogoGramWallet" : "IntroLogo")
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("\(APP_NAME) \(appVersion)")
                    .font(.system(size: 17, weight: .semibold))
                Text(LocalizedStringKey("[\(websiteTitle)](\(APP_WEBSITE_URL))"))
                    .font(.system(size: 14, weight: .regular))
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            UIApplication.shared.open(url)
            return .handled
        })
    }
    
    var longDescription: some View {
        InsetSection {
            InsetCell {
                Text(LocalizedStringKey(lang("$about_description1") + "\n\n" + lang("$about_description2")))
            }
        }
    }
    
    var resources: some View {
        InsetSection(dividersInset: 46) {
            if !IS_GRAM_WALLET {
                Item(
                    icon: "PlayIcon",
                    text: lang("Watch Video about Features"),
                    onTap: onWatch
                )
            }
            Item(
                icon: "FireIcon",
                text: lang("Enjoy Monthly Updates in Blog"),
                onTap: onBlog
            )
            Item(
                icon: "BookIcon",
                text: lang("Learn New Things in Help Center"),
                onTap: onLearn
            )
        } header: {
            Text(lang("%app_name% Resources", arg1: APP_NAME))
        }
    }
    
    func onWatch() {
        AppActions.openTipsChannel()
    }
    
    func onBlog() {
        open(APP_BLOG_URL)
    }
    
    func onLearn() {
        open(HELP_CENTER_URL)
    }
    
    @ViewBuilder
    var legal: some View {
        InsetSection(dividersInset: 46) {
            Item(
                icon: "ResponsibilityIcon30",
                text: lang("Use Responsibly"),
                onTap: onUseResponsibly
            )
        }
        InsetSection(dividersInset: 46) {
            Item(
                icon: "TermsIcon",
                text: lang("Terms of Use"),
                onTap: onTerms
            )
            Item(
                icon: "TermsIcon",
                text: lang("Privacy Policy"),
                onTap: onPrivacyPolicy
            )
        }
        .padding(.bottom, 32)
    }
    
    func onUseResponsibly() {
        let vc = UseResponsiblyVC()
        topWViewController()?.navigationController?.pushViewController(vc, animated: true)
    }
    
    func onTerms() {
        let url = URL(string: APP_TERMS_OF_USE_URL)!
        let title = lang("Terms of Use")
        topWViewController()?.navigationController?.pushPlainWebView(title: title, url: url)
    }
    
    func onPrivacyPolicy() {
        let url = URL(string: APP_PRIVACY_POLICY_URL)!
        let title = lang("Privacy Policy")
        topWViewController()?.navigationController?.pushPlainWebView(title: title, url: url)
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
            .foregroundStyle(Color.air.primaryLabel)
            .backportGeometryGroup()
        }
    }
}
