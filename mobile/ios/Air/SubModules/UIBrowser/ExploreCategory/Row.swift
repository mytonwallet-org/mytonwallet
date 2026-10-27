//
//  Row.swift
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
        HStack(spacing: 14) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 114)
    }
    
    private func textsAndButton() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(site.name).textStyle(.body)
                    .lineLimit(1)

                if site.tgUrl != nil {
                    Image.airBundle("TelegramLogo20")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color.air.secondaryLabel.opacity(0.5))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 18)
            .padding(.top, 11)
                
            Spacer().frame(height: 4)
                
            Text(site.description).textStyle(.footnote)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(height: 16)
            
            Spacer(minLength: 0)
            
            Button(action: openAction) {
                Text(lang("Open"))
                    .frame(height: 16)
                    .foregroundStyle(.tint)
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
