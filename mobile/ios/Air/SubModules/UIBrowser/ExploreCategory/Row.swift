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
    
    var site: ApiSite
    
    var openAction: () -> ()
    
    var body: some View {
        HStack(spacing: 10) {
            KFImage(URL(string: site.icon))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: 12))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(site.name)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                Text(site.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button(action: openAction) {
                HStack(spacing: 2) {
                    if site.shouldOpenExternally {
                        Image.airBundle("TelegramLogo20")
                            .padding(.leading, -4)
                            .padding(.vertical, -6)
                    }
                    Text(lang("Open"))
                }
            }
            .buttonStyle(OpenButtonStyle())
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    ExploreCategoryRow(site: .sampleFeaturedTelegram, openAction: {})
        .border(.red)
        .padding(20)
}
#endif
