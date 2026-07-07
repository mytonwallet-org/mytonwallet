
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

struct DappHeaderView: View {
    
    var dapp: ApiDapp
    var accountContext: AccountContext
    var customTokenBalance: BigInt? = nil
    var customToken: ApiToken? = nil
    
    var showWarning: Bool { dapp.shouldShowUrlTrustStatusWarning }
    
    var body: some View {
        WithPerceptionTracking {
            headerContentLayer
                .background {
                    headerBackgroundLayer
                }
            .truncationMode(.middle)
            .allowsTightening(true)
            .foregroundStyle(.white)
            .clipShape(.containerRelative)
            .containerShape(.rect(cornerRadius: 26))
            .padding(.horizontal, 16)
        }
    }

    private var headerBackgroundLayer: some View {
        ZStack {
            Background()
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                trailingBackgroundPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trailingBackgroundPanel: some View {
        ZStack {
            BackgroundBlur(radius: 16)
            Rectangle()
                .fill(.black)
                .opacity(0.1)
                .blendMode(.plusDarker)
        }
        .clipShape(HeaderLine())
        .padding(.leading, -24)
    }

    private var headerContentLayer: some View {
        HStack(alignment: .center, spacing: 8) {
            leadingContent
                .padding(.leading, 16)
                .frame(minWidth: 0, maxWidth: leadingTextMaxWidth, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                trailingTextColumn
                icon
            }
            .frame(minWidth: 0, maxWidth: trailingTextMaxWidth, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 14)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
    }

    @State private var contentWidth: CGFloat = 0

    private var leadingTextMaxWidth: CGFloat? {
        guard contentWidth > 0 else { return nil }
        let ratio = balancedTextRatio
        return max(flexibleTextWidth * ratio, 0)
    }

    private var trailingTextMaxWidth: CGFloat? {
        guard contentWidth > 0 else { return nil }
        let ratio = balancedTextRatio
        return max(flexibleTextWidth * (1 - ratio), 0)
    }

    private var flexibleTextWidth: CGFloat {
        max(contentWidth - 16 - 12 - 4, 0)
    }

    /// Share of flexible width given to the wallet side (remainder goes to dapp text).
    private var balancedTextRatio: CGFloat {
        let leadingWeight = CGFloat(max(accountContext.account.displayName.count, 1))
        let trailingWeight = CGFloat(max(dapp.name.count + dapp.displayUrl.count + (showWarning ? 2 : 0), 1))
        let ratio = leadingWeight / (leadingWeight + trailingWeight)
        return min(max(ratio, 0.32), 0.68)
    }

    private var leadingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accountContext.account.displayName)
                .font(.system(size: 16, weight: .medium))
                .frame(minHeight: 22)
            if let customToken, let customTokenBalance {
                Text(TokenAmount(customTokenBalance, customToken).formatted(.defaultAdaptive))
                    .font(.system(size: 14, weight: .regular))
                    .opacity(0.75)
            } else if let balance = accountContext.balance {
                Text(balance.formatted(.baseCurrencyEquivalent))
                    .font(.system(size: 14, weight: .regular))
                    .opacity(0.75)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var trailingTextColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            title
                .lineLimit(3)
                .skeletonPlaceholder(
                    surface: .colored,
                    barInset: .init(top: 0, leading: 0, bottom: 1, trailing: 0)
                )
            transfer
                .font(.system(size: 14, weight: .regular))
                .lineLimit(3)
                .skeletonPlaceholder(surface: .colored, barInset: .init(top: 1, leading: 0, bottom: 0, trailing: 0))
        }
        .multilineTextAlignment(.trailing)
    }
    
    private var title: some View {
        Text(dapp.name)
            .font(.system(size: 16, weight: .medium))
            .frame(minHeight: 22)
    }
    
    private var icon: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.air.secondaryFill)
            .frame(width: 40, height: 40)
            .overlay {
                DappIcon(iconUrl: dapp.iconUrl)
            }
            .clipShape(.rect(cornerRadius: 12))
            .skeletonPlaceholder(surface: .colored, cornerRadius: 12)
    }

    @ViewBuilder
    private var transfer: some View {
        let dappUrlText = Text(dapp.displayUrl)
            .foregroundColor(.white.opacity(0.75))
        if showWarning {
            let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                .foregroundColor(dapp.resolvedUrlTrustStatus == .dangerous ? Color.air.error : .orange)
                .fontWeight(.bold)
            Text("\(dappUrlText)\u{00A0}\(warning)")
                .imageScale(.small)
                .contentShape(.rect)
                .onTapGesture {
                    showDappOriginWarningTip(urlTrustStatus: self.dapp.resolvedUrlTrustStatus)
                }
        } else {
            Text("\(dappUrlText)")
        }
    }
}

private struct AngledArea: Shape {
    
    var x: CGFloat
    var radiusMultiplier: CGFloat
    
    nonisolated func path(in rect: CGRect) -> Path {
        Path {
            let h = rect.height
            let w = rect.width
            let x = w * x
            let r = (w + h) * radiusMultiplier
            $0.move(to: CGPoint(x: x, y: 2 * h))
            $0.addRelativeArc(center: CGPoint(x: x + r, y: 2 * h), radius: r, startAngle: .degrees(-180), delta: .degrees(90))
            $0.addLine(to: CGPoint(x: 0, y: 0))
            $0.addLine(to: CGPoint(x: 0, y: 2 * h))
            $0.addLine(to: CGPoint(x: x, y: 2 * h))
            $0.closeSubpath()
        }
    }
}

private struct HeaderLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path {
            let h = rect.height
            let w = rect.width
            let dx = 0.3 * h
            let dw = 7.0
            let ds = 5.0
            let x1 = dw + ds
            let r = 10.0
            $0.move(to: CGPoint(x: 0, y: 0))
            $0.addArc(
                tangent1End: CGPoint(x: dx, y: h/2),
                tangent2End: CGPoint(x: 0, y: h),
                radius: r
            )
            $0.addLine(to: CGPoint(x: 0, y: h))
            $0.addLine(to: CGPoint(x: dw, y: h))
            $0.addArc(
                tangent1End: CGPoint(x: dw + dx, y: h/2),
                tangent2End: CGPoint(x: dw, y: 0),
                radius: r + dw * 0.5
            )
            $0.addLine(to: CGPoint(x: dw, y: 0))
            $0.closeSubpath()
            
            $0.move(to: CGPoint(x: x1, y: 0))
            $0.addArc(
                tangent1End: CGPoint(x: x1 + dx, y: h/2),
                tangent2End: CGPoint(x: x1, y: h),
                radius: r + x1 * 0.5
            )
            $0.addLine(to: CGPoint(x: x1, y: h))
            $0.addLine(to: CGPoint(x: w, y: h))
            $0.addLine(to: CGPoint(x: w, y: 0))
            
        }
    }
}

private struct Background: View {
    var body: some View {
        ZStack {
            Rectangle()
            AngledArea(x: 0.05, radiusMultiplier: 0.9)
                .fill(.white)
                .opacity(0.1)
            AngledArea(x: 0.17, radiusMultiplier: 0.7)
                .fill(.white)
                .opacity(0.1)
            AngledArea(x: 0.3, radiusMultiplier: 0.55)
                .fill(.white)
                .opacity(0.1)
        }
        .foregroundStyle(.tint)
    }
}

#if DEBUG
private struct DappHeaderPreviewCase: Identifiable {
    let id: String
    let title: String
    let account: MAccount
    let dapp: ApiDapp
}

private enum DappHeaderPreviewData {
    private static let tonAddress = "EQBvW8Z5huBkMJYdnfTenE87hwP9bLy5tDXTDQDF7FyoE6xB"
    private static let iconUrl = ApiDapp.sample.iconUrl

    private static let namedWallet = MAccount(
        id: "preview-named",
        title: "Main Wallet",
        type: .mnemonic,
        byChain: [.ton: .init(address: tonAddress)]
    )

    private static let unnamedWallet = MAccount(
        id: "preview-unnamed",
        title: nil,
        type: .mnemonic,
        byChain: [.ton: .init(address: tonAddress)]
    )

    private static let longNameWallet = MAccount(
        id: "preview-long-wallet",
        title: "Very Long Subwallet Name For Truncation",
        type: .mnemonic,
        byChain: [.ton: .init(address: tonAddress)]
    )

    private static let viewOnlyWallet = MAccount(
        id: "preview-view",
        title: "Watch Only",
        type: .view,
        byChain: [.ton: .init(address: tonAddress)]
    )

    private static func dapp(
        name: String,
        url: String,
        urlTrustStatus: ApiDappUrlTrustStatus? = nil
    ) -> ApiDapp {
        ApiDapp(
            url: url,
            name: name,
            iconUrl: iconUrl,
            connectedAt: nil,
            urlTrustStatus: urlTrustStatus,
            sse: nil
        )
    }

    static let cases: [DappHeaderPreviewCase] = [
        .init(id: "default", title: "Named wallet · default dapp", account: namedWallet, dapp: .sample),
        .init(id: "unnamed-wallet", title: "Unnamed wallet · address fallback", account: unnamedWallet, dapp: .sample),
        .init(id: "long-wallet", title: "Long wallet name", account: longNameWallet, dapp: .sample),
        .init(id: "view-only", title: "View-only wallet", account: viewOnlyWallet, dapp: .sample),
        .init(
            id: "long-dapp-name",
            title: "Long dapp name",
            account: namedWallet,
            dapp: dapp(name: "Storm Trade Premium Analytics Dashboard", url: "https://app.storm.tg")
        ),
        .init(
            id: "long-url",
            title: "Long dapp origin",
            account: namedWallet,
            dapp: dapp(name: "Bidask", url: "https://analytics.staging-west.app.bidask.finance")
        ),
        .init(
            id: "verified",
            title: "Verified origin",
            account: namedWallet,
            dapp: dapp(name: "MyWallet", url: "https://mywallet.io", urlTrustStatus: .verified)
        ),
        .init(
            id: "unknown",
            title: "Unknown origin",
            account: namedWallet,
            dapp: dapp(name: "Unknown Dapp", url: "https://unknown.example.com", urlTrustStatus: .unknown)
        ),
        .init(
            id: "dangerous",
            title: "Dangerous origin",
            account: namedWallet,
            dapp: dapp(name: "Scam Site", url: "https://scam.example.com", urlTrustStatus: .dangerous)
        ),
        .init(
            id: "long-both",
            title: "Long wallet and dapp",
            account: longNameWallet,
            dapp: dapp(
                name: "Extremely Long Dapp Name That Should Wrap To Multiple Lines",
                url: "https://very-long-subdomain.example-wallet.apps.tonkeeper.com"
            )
        ),
    ] + ApiDapp.sampleList.enumerated().map { index, dapp in
        DappHeaderPreviewCase(
            id: "sample-\(index)",
            title: "Sample dapp · \(dapp.name)",
            account: namedWallet,
            dapp: dapp
        )
    }
}

private struct DappHeaderPreviewGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(DappHeaderPreviewData.cases) { previewCase in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(previewCase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        DappHeaderView(
                            dapp: previewCase.dapp,
                            accountContext: AccountContext(source: .constant(previewCase.account))
                        )
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.air.groupedBackground)
    }
}

@available(iOS 18, *)
#Preview("Normal") {
    DappHeaderPreviewGallery()
}
#Preview("Skeletons") {
    DappHeaderPreviewGallery()
         .skeletonContainer()
}
#endif
