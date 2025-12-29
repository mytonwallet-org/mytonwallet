
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext
import UIComponents

struct FeaturedDappCell: View {
    
    var item: ApiSite
    
    var isHighlighted: Bool
    
    var openAction: () -> ()
    
    private let borderWidth: CGFloat = 4
    
    var body: some View {
        let url: URL? = if let expanded = item.extendedIcon { URL(string: expanded) } else { URL(string: item.icon) }
        ZStack(alignment: .top) {
            Color.clear
            VStack(spacing: 0) {
                KFImage(url)
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                KFImage(url)
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(y: -1)
                    .zIndex(-1)
            }
        }
        .frame(height: 190, alignment: .top)
        .overlay(alignment: .bottom) {
            overlayContent
        }
        .contentShape(.containerRelative)
        .highlightOverlay(isHighlighted)
        .clipShape(.containerRelative)
        .containerShape(.rect(cornerRadius: S.featuredDappCornerRadius))
        .overlay {
            if item.withBorder == true {
                RoundedRectangle(cornerRadius: S.featuredDappCornerRadius)
                    .stroke(Color(WTheme.tint), lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badgeText = item.badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(WTheme.tint), in: .rect(cornerRadius: 6))
                    .padding(.top, -6)
                    .padding(.trailing, 20)
            }
        }
    }
    
    @ViewBuilder
    var overlayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
//            titleLabels
            openSection
        }
        .environment(\.colorScheme, .light)
    }
    
    @ViewBuilder
    var titleLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker = item.test_kicker {
                Text(kicker)
                    .textCase(.uppercase)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Material.thin)
            }
            Text(item.test_shortTitle)
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    var openSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                KFImage(URL(string: item.icon))
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 11))
                    .padding(.trailing, 10)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Material.thin)
                        .lineLimit(2)
                }
            }
                
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

#if DEBUG
#Preview {
    FeaturedDappCell(item: .sampleFeaturedTelegram, isHighlighted: false, openAction: {})
        .padding(.horizontal, 20)
}
#endif
