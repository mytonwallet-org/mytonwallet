
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext
import UIComponents

private let featuredDappCornerRadius: CGFloat = IOS_26_MODE_ENABLED ? 22 : 14

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
        .containerShape(.rect(cornerRadius: featuredDappCornerRadius))
        .overlay {
            if item.withBorder == true {
                RoundedRectangle(cornerRadius: featuredDappCornerRadius)
                    .stroke(badgeShapeStyle, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badgeText = item.badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(minHeight: 18)
                    .background(badgeShapeStyle, in: .rect(cornerRadius: 6))
                    .padding(.top, -6)
                    .padding(.trailing, 20)
            }
        }
    }
    
    private var badgeShapeStyle: AnyShapeStyle {
        guard let colors = item.borderColor, !colors.isEmpty else {
            return AnyShapeStyle(.tint)
        }
        let mappedColors = colors.map { Color(UIColor(hex: $0)) }
        let gradientColors = mappedColors.count == 1 ? [mappedColors[0], mappedColors[0]] : mappedColors
        return AnyShapeStyle(LinearGradient(colors: gradientColors, startPoint: .trailing, endPoint: .leading))
    }
    
    @ViewBuilder
    var overlayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            openSection
        }
        .environment(\.colorScheme, .light)
    }
    
    @ViewBuilder
    var openSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                if false {
                    KFImage(URL(string: item.icon))
                        .resizable()
                        .loadDiskFileSynchronously(false)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(.rect(cornerRadius: 11))
                        .padding(.trailing, 10)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(item.name)
                            .lineLimit(2)
                        if item.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .imageScale(.small)
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
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
