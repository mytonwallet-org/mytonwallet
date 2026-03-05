//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Kingfisher
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

struct ExploreCategoryRow: View {
    let site: ApiSite
    let openAction: () -> ()
    
    private let cornerRadius: CGFloat = 23
    
    var body: some View {
        HStack(spacing: 10) {
            KFImage(URL(string: site.icon))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: cornerRadius))
                .frame(width: 88, height: 88)
                .applyModifierConditionally {
                    if #available(iOS 26.0, *) {
                        $0.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    } else {
                        $0
                    }
                }
                .padding(.vertical, 13)
            
            textsAndButton()
            
            Spacer(minLength: 0)
        }
        .frame(height: 114)
    }
    
    private func textsAndButton() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(site.name).font(.system(size: 15, weight: .semibold))
                .fixedSize()
                .padding(.top, 11)
                
            Spacer().frame(height: 4)
                
            Text(site.description).font(.system(size: 14))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .foregroundStyle(Color(WTheme.secondaryLabel))
            
            Spacer(minLength: 0)
            
            Button(action: openAction) {
                HStack(spacing: 2) {
                    if site.shouldOpenExternally {
                        Image.airBundle("TelegramLogo20")
                            .padding(.leading, -4)
                            .padding(.vertical, -6)
                    }
                    Text(lang("Open"))
                }
                .foregroundStyle(Color(WTheme.tint))
            }
            .buttonStyle(OpenButtonStyle())
            .padding(.bottom, 10)
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    VStack(spacing: 0) {
        ExploreCategoryRow(site: .sampleFeatured(), openAction: {})
        Rectangle().fill(Color.gray).frame(height: 1)
        ExploreCategoryRow(site: .sampleFeaturedTelegram, openAction: {})
        Spacer()
    }
    .padding(.horizontal, 20)
}
#endif
