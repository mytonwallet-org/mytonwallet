import Perception
import ProtectedAction
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct DappConfirmationHeaderView: ConfirmationContent {
    enum Action {
        case connect
        case signData
        case send(ApiUpdate.DappSendTransactions)
    }

    enum Asset {
        case token(TokenAmount)
        case nft(ApiNftTransferPayload)
    }

    let dapp: ApiDapp
    let action: Action

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 16) {
                if case .connect = action {
                    DappIcon(iconUrl: dapp.iconUrl)
                        .frame(width: 80, height: 80)
                        .clipShape(.rect(cornerRadius: 16))
                        .accessibilityHidden(true)
                } else if !assets.isEmpty {
                    assetIcons
                }
                VStack(spacing: 12) {
                    summary
                        .frame(minHeight: 42)
                    destination
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 172)
            .padding(.horizontal, 16)
            .padding(.vertical, 33)
            .multilineTextAlignment(.center)
        }
    }

    var compactRepresentation: some View {
        WithPerceptionTracking {
            CompactActionSummary {
                DappIcon(iconUrl: dapp.iconUrl)
                    .clipShape(.rect(cornerRadius: 5))
            } label: {
                Text(compactSummary)
                    .textStyle(.bodyEmphasized)
                    + Text(" · ")
                    + Text(dapp.name).textStyle(.bodyEmphasized)
            }
        }
    }

    var assets: [Asset] {
        guard case .send(let request) = action, request.shouldHideTransfers != true else { return [] }
        guard !request.transactions.contains(where: { $0.isDangerous }) else { return [] }
        return request.transactions.map { transaction in
            if let payload = transaction.nftTransferPayload {
                return .nft(payload)
            }
            return .token(TokenAmount(transaction.effectiveAmount, transaction.getToken(chain: request.operationChain)))
        }
    }

    private var assetIcons: some View {
        let visibleAssets = Array(assets.prefix(10))
        return GeometryReader { geometry in
            let preferredStep: CGFloat = visibleAssets.count > 3 ? 28 : 56
            let step = min(preferredStep, max(0, (geometry.size.width - 80) / CGFloat(max(visibleAssets.count - 1, 1))))
            HStack(spacing: step - 80) {
                ForEach(visibleAssets.indices, id: \.self) { index in
                    assetIcon(visibleAssets[index])
                        .overlay {
                            if visibleAssets.count > 1 {
                                RoundedRectangle(cornerRadius: cornerRadius(for: visibleAssets[index]))
                                    .strokeBorder(Color.air.sheetBackground, lineWidth: 2)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 80)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func assetIcon(_ asset: Asset) -> some View {
        switch asset {
        case .token(let amount):
            WUIIconViewToken(
                token: amount.token,
                isWalletView: false,
                showldShowChain: false,
                size: 80,
                chainSize: 0,
                chainBorderWidth: 0,
                chainHorizontalOffset: 0,
                chainVerticalOffset: 0
            )
            .frame(width: 80, height: 80)
        case .nft(let payload):
            Group {
                if let nft = payload.nft {
                    NftImage(nft: nft, animateIfPossible: false)
                } else {
                    Image.airBundle("NoNftImage2")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(.rect(cornerRadius: 16))
        }
    }

    private func cornerRadius(for asset: Asset) -> CGFloat {
        switch asset {
        case .token: 40
        case .nft: 16
        }
    }

    @ViewBuilder
    private var summary: some View {
        if case .connect = action {
            styledTitle(dapp.name, emphasized: nil)
        } else if assets.count == 1, let asset = assets.first {
            switch asset {
            case .token(let amount):
                AmountText(
                    amount: TokenAmount(-abs(amount.amount), amount.token).roundedForDisplay,
                    format: .init(showMinus: true),
                    integerFont: .compactRounded(ofSize: 34, weight: .bold),
                    fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                    symbolFont: .compactRounded(ofSize: 28, weight: .bold),
                    integerColor: .label,
                    fractionColor: .air.secondaryLabel,
                    symbolColor: .air.secondaryLabel
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            case .nft(let payload):
                nftTitle(nftName(payload))
            }
        } else {
            styledTitle(summaryTitle, emphasized: assets.isEmpty ? nil : String(assets.count))
        }
    }

    private func nftTitle(_ name: String) -> some View {
        let suffixRange = name.range(of: #"\s+#[0-9]+$"#, options: .regularExpression)
        return styledTitle(name, emphasized: suffixRange.map { String(name[..<$0.lowerBound]) })
    }

    private func styledTitle(_ title: String, emphasized: String?) -> some View {
        var attributed = AttributedString(title)
        attributed.font = .system(size: emphasized == nil ? 30 : 24, weight: .bold)
        attributed.foregroundColor = emphasized == nil ? Color.primary : Color.air.secondaryLabel
        if let emphasized, let range = attributed.range(of: emphasized) {
            attributed[range].font = .system(size: 30, weight: .bold)
            attributed[range].foregroundColor = .primary
        }
        return Text(attributed)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    private var summaryTitle: String {
        switch action {
        case .connect: lang("Connect")
        case .signData: lang("Sign Data")
        case .send:
            assets.isEmpty ? lang("Unknown Transfer") : L10n.manyTransactions(count: assets.count)
        }
    }

    private var compactSummary: String {
        if assets.count == 1, let asset = assets.first {
            switch asset {
            case .token(let amount): return amount.formatted(.defaultAdaptive)
            case .nft(let payload): return nftName(payload)
            }
        }
        return summaryTitle
    }

    private func nftName(_ payload: ApiNftTransferPayload) -> String {
        payload.nft?.name?.nilIfEmpty ?? payload.nftName?.nilIfEmpty ?? lang("NFT")
    }

    @ViewBuilder
    private var destination: some View {
        if case .connect = action {
            Text(lang("Connect"))
                .foregroundStyle(Color.air.secondaryLabel)
                .textStyle(.body)
                .frame(minHeight: 22)
        } else {
            dappDestination
        }
    }

    private var dappDestination: some View {
        HStack(spacing: 6) {
            if let prefix = destinationPrefix {
                Text(prefix)
                    .fixedSize()
            }
            HStack(spacing: 4) {
                DappIcon(iconUrl: dapp.iconUrl)
                    .frame(width: 18, height: 18)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text(dapp.name)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .textStyle(.body)
        .frame(minHeight: 22)
    }

    private var destinationPrefix: String? {
        switch action {
        case .connect: nil
        case .signData: lang("$dapp_sign_data_for_prefix")
        case .send(let request): request.transactions.count <= 1 ? nil : lang("to")
        }
    }
}
