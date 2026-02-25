import Kingfisher
import SwiftUI
import UIComponents
import WalletCore

#if DEBUG
@available(iOS 17, *)
#Preview {
    VStack(spacing: 40) {
        ExploreScreenFeaturedDappView(site: .sampleFeatured(), onTap: {})
            .aspectRatio(2, contentMode: .fit)
        ExploreScreenFeaturedDappView(site: .sampleFeaturedTelegram, onTap: {})
            .aspectRatio(2, contentMode: .fit)
        Spacer()
    }
    .padding(.horizontal, 20)
    .background(Color.air.groupedBackground)
}
#endif

struct ExploreScreenFeaturedDappView: View {
    let site: ApiSite
    let onTap: () -> Void

    private let cornerRadius: Double = 22

    private let iOS17Available: Bool = if #available(iOS 17.0, *) {
        true
    } else {
        false
    }

    var body: some View {
        VStack {
            Spacer()
            footerInformationView
        }
        .background(alignment: .topLeading) { backgroundImageView }
        .onTapWithHighlightInScroll(action: onTap)
        .outerStrokeOverlay(shapeStyleGradient,
                            cornerRadius: cornerRadius,
                            lineWidth: 2,
                            clipToStroke: true,
                            isVisible: site.withBorder == true)
        .shadow(style: .medium)
        .overlay(alignment: .topTrailing) {
            badgeLabel.padding(EdgeInsets(top: -6, leading: 0, bottom: 0, trailing: 20))
        }
    }

    // MARK: Badge Text

    @ViewBuilder private var badgeLabel: some View {
        if let badgeText = site.badgeText, !badgeText.isEmpty {
            Text(badgeText).font(.system(size: 11, weight: .semibold))
                .frame(height: 14) // should be lineHeight
                .foregroundStyle(.white)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .background(shapeStyleGradient, in: .rect(cornerRadius: 6))
        }
    }

    // MARK: Background Image

    private var backgroundImageView: some View {
        let url: URL? = if let expanded = site.extendedIcon {
            URL(string: expanded)
        } else {
            URL(string: site.icon)
        }

        return KFImage(url).resizable()
            .loadDiskFileSynchronously(false)
            .aspectRatio(contentMode: .fill)
    }

    // MARK: Information

    private var footerInformationView: some View {
        HStack(spacing: 0) {
            if let iconURL = URL(string: site.icon) {
                KFImage(iconURL)
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 4) {
                    Text(site.name).font(.system(size: 15, weight: .semibold))
                        .kerning(-0.28)
                        .lineLimit(1)
                        .frame(height: 18) // should lineHeight
                        .foregroundStyle(.white)

                    if site.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                            .foregroundStyle(.blue)
                    }
                }

                Text(site.description).font(.system(size: 13, weight: .medium))
                    .kerning(-0.55)
                    .applyModifierConditionally {
                        if #available(iOS 26.0, *) {
                            $0.lineHeight(.exact(points: 16))
                        } else {
                            $0
                        }
                    }
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 14, trailing: 16))
    }

    // MARK: Gradient

    private var shapeStyleGradient: AnyShapeStyle {
        var tint: AnyShapeStyle { AnyShapeStyle(.tint) }
        guard let colors = site.borderColor?.compactMap({ Color(UIColor(hex: $0)) }) else { return tint }
        guard let firstColor = colors.first else { return tint }

        let gradientColors = colors.count > 1 ? colors : [firstColor, firstColor]
        let gradient = LinearGradient(colors: gradientColors, startPoint: .trailing, endPoint: .leading)
        return AnyShapeStyle(gradient)
    }
}
