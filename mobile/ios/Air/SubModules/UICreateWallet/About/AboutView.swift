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
    
    var body: some View {
        InsetList {
            header
                .padding(.top, 42)
            longDescription
            resources
                .padding(.bottom, 32)
        }
        .backportScrollBounceBehaviorBasedOnSize()
    }
    
    @ViewBuilder
    var header: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        VStack(spacing: 14) {
            Image.airBundle("IntroLogo")
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("\(lang("MyTonWallet")) \(appVersion)")
                    .font(.system(size: 17, weight: .semibold))
                Text("[mytonwallet.io](https://mytonwallet.io)")
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
            Item(
                icon: "PlayIcon",
                text: lang("Watch Video about Features"),
                onTap: onWatch
            )
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
            Text(lang("MyTonWallet Resources"))
        }
    }
    
    func onWatch() {
        open("https://t.me/MyTonWalletTips")
    }
    
    func onBlog() {
        open("https://mytonwallet.io/en/blog")
    }
    
    func onLearn() {
        open("https://help.mytonwallet.io")
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

