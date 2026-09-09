import SwiftUI
import UIComponents
import WalletContext

struct ActionMenuItem: View {
    let item: SplitHomeActionItem

    var body: some View {
        VStack(spacing: 0) {
            ActionMenuIcon(item: item)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text(item.title)
                .textStyle(.callout)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.top, 2)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct ActionMenuIcon: View {
    let item: SplitHomeActionItem

    var body: some View {
        ZStack {
            ActionMenuIconBackground(item: item)
            ActionMenuGlyph(item: item)
        }
    }
}

private struct ActionMenuIconBackground: View {
    let item: SplitHomeActionItem
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            sharedContent
                .glassEffect(.clear, in: shape.inset(by: 1))
        } else {
            sharedContent
        }
    }

    private var sharedContent: some View {
        Image.airBundle(item.actionMenuBackgroundAssetName)
            .resizable()
            .renderingMode(.original)
            .frame(width: 67, height: 67)
            .clipShape(shape)
    }
}

#Preview {
    ActionMenuIcon(item: SplitHomeActionItem.buy)
}

private struct ActionMenuGlyph: View {
    let item: SplitHomeActionItem

    var body: some View {
        Image.airBundle(item.actionMenuGlyphAssetName)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: item.actionMenuGlyphSize.width, height: item.actionMenuGlyphSize.height)
            .blendMode(.plusLighter)
    }
}

private extension SplitHomeActionItem {
    var actionMenuBackgroundAssetName: String {
        switch self {
        case .buy: "ActionMenuBuyBackground"
        case .deposit: "ActionMenuFundBackground"
        case .swap: "ActionMenuTradeBackground"
        case .sell: "ActionMenuSellBackground"
        case .send: "ActionMenuSendBackground"
        case .earn: "ActionMenuEarnBackground"
        case .scan: "ActionMenuScanBackground"
        }
    }

    var actionMenuGlyphAssetName: String {
        switch self {
        case .buy: "ActionMenuBuyGlyph"
        case .deposit: "ActionMenuFundGlyph"
        case .swap: "ActionMenuTradeGlyph"
        case .sell: "ActionMenuSellGlyph"
        case .send: "ActionMenuSendGlyph"
        case .earn: "ActionMenuEarnGlyph"
        case .scan: "ActionMenuScanGlyph"
        }
    }

    var actionMenuGlyphSize: CGSize {
        switch self {
        case .buy: CGSize(width: 41, height: 37)
        case .deposit: CGSize(width: 28, height: 34)
        case .swap: CGSize(width: 35, height: 42)
        case .sell: CGSize(width: 24, height: 40)
        case .send: CGSize(width: 28, height: 34)
        case .earn: CGSize(width: 36.002, height: 35.1)
        case .scan: CGSize(width: 33.841, height: 33.841)
        }
    }
}
