//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Kingfisher

struct ExploreCategoryRow: View {
    let site: ApiSite
    let openAction: () -> ()
    
    var body: some View {
        HStack(spacing: 10) {
            KFImage(URL(string: site.icon))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: 12))
                .frame(width: 48, height: 48)
                .padding(.vertical, 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                Text(site.description).font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            }
          
            Spacer(minLength: 12)
          
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
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
  VStack(spacing: 0) {
    ExploreCategoryRow(site: .sampleFeatured(), openAction: {})
    ExploreCategoryRow(site: .sampleFeaturedTelegram, openAction: {})
    Spacer()
  }
  .padding(.horizontal, 20)
  .background { Color.orange.opacity(0.1) }
}
#endif
