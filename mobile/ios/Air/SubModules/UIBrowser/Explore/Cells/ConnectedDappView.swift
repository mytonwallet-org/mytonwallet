import Kingfisher
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

#if DEBUG
#Preview {
    let dapp = ApiDapp.sample
    let longName = "LongName_longName_longName_longName"
    VStack(spacing: 40) {
        Spacer()
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ConnectedDappButton(dappName: longName, iconURL: dapp.iconUrl, layoutVariant: .compact, onTap: {})
                ConnectedDappsSettingsButton(layoutVariant: .compact, onTap: {})
            }
        }
        .backportScrollClipDisabled()
        HStack(spacing: 8) {
            ConnectedDappButton(dappName: longName, iconURL: dapp.iconUrl, layoutVariant: .regular, onTap: {})
            ConnectedDappsSettingsButton(layoutVariant: .regular, onTap: {})
        }
        Spacer()
    }
    .padding(.horizontal, 20)
    .background { Color.air.groupedBackground.ignoresSafeArea() }
}
#endif

struct ConnectedDappButton: View {
    let dappName: String
    let iconURL: String
    let layoutVariant: LayoutSizeVariant
    let onTap: () -> Void

    var body: some View {
        ConnectedDappGenericView(title: dappName,
                                 layoutVariant: layoutVariant,
                                 regularSizeWithStroke: false,
                                 image: {
                                     KFImage(URL(string: iconURL))
                                         .placeholder { connectedDappBackgroundGradient }
                                         .resizable()
                                 },
                                 onTap: onTap)
    }
}

struct ConnectedDappsSettingsButton: View {
    let layoutVariant: LayoutSizeVariant
    let onTap: () -> Void

    private var title: String? {
        switch layoutVariant {
        case .compact: nil
        case .regular: lang("Settings")
        }
    }

    var body: some View {
        ConnectedDappGenericView(title: title,
                                 layoutVariant: layoutVariant,
                                 regularSizeWithStroke: true,
                                 image: {
                                     Image.airBundle("Settings60")
                                         .resizable()
                                         .background { connectedDappBackgroundGradient }
                                 },
                                 onTap: onTap)
    }
}

private struct ConnectedDappGenericView<ImageView: View>: View {
    let title: String?
    let layoutVariant: LayoutSizeVariant
    let regularSizeWithStroke: Bool
    let image: () -> ImageView
    let onTap: () -> Void

    var body: some View {
        let imageSideLength: Double = switch layoutVariant {
        case .compact: 34
        case .regular: 60
        }

        switch layoutVariant {
        case .compact:
            HStack(alignment: .center, spacing: 8) {
                image().frame(width: imageSideLength, height: imageSideLength)
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 0))

                if let title { // settings button has no title in compact layout
                    Text(title).font(.system(size: 15, weight: .medium))
                        .kerning(-0.28)
                        .frame(maxWidth: 140)
                        .frame(height: 15) // should be lineHeight
                        .padding(.trailing, 12)
                }
            }
            .background { connectedDappBackgroundGradient }
            .onTapWithHighlightInScroll(action: onTap)
            .innerStrokeOverlay(Color.air.groupedItem, cornerRadius: 13, lineWidth: 1, clipToStroke: true)
            .shadow(style: .light)

        case .regular:
            VStack(alignment: .center, spacing: 8) {
                image().frame(width: imageSideLength, height: imageSideLength)
                    .onTapWithHighlightInScroll(action: onTap)
                    .innerStrokeOverlay(regularSizeWithStroke ? Color.air.groupedItem : Color.clear,
                                        cornerRadius: 16,
                                        lineWidth: 1,
                                        clipToStroke: true)

                // For regular size, title is always expected, use " " as a fallback
                Text(title ?? " ").font(.system(size: 12, weight: .medium))
                    .kerning(-0.4)
                    .frame(height: 12) // should be lineHeight
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .frame(maxWidth: imageSideLength)
                    .padding(.bottom, 8)
            }
        }
    }
}

private var connectedDappBackgroundGradient: LinearGradient {
    LinearGradient(colors: [.air.groupedBackground, .air.background], startPoint: .top, endPoint: .bottom)
}
