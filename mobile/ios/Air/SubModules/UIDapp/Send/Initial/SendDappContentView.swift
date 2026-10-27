
import SwiftUI
import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

struct SendDappViewOrPlaceholder: View {
    var accountContext: AccountContext
    var request: ApiUpdate.DappSendTransactions?
    var heroAmount: BaseCurrencyAmount?
    var onShowDetail: (ApiDappTransfer) -> ()
    
    var body: some View {
        if let request {
            SendDappContentView(
                accountContext: accountContext,
                request: request,
                heroAmount: heroAmount,
                onShowDetail: onShowDetail
            )
            .transition(.opacity.animation(.default))
        } else {
            SendDappPlaceholderView(accountContext: accountContext)
                .transition(.opacity.animation(.default))
        }
    }
}

private struct SendDappContentView: View {
    var accountContext: AccountContext
    var request: ApiUpdate.DappSendTransactions
    var heroAmount: BaseCurrencyAmount?
    var onShowDetail: (ApiDappTransfer) -> ()
    
    private var operationChain: ApiChain { request.operationChain }
    private var transactionsCount: Int { request.transactions.count }
    private var sortedTransactions: [ApiDappTransfer] {
        request.transactions.sorted { lhs, rhs in
            transactionSortCost(lhs) > transactionSortCost(rhs)
        }
    }
    
    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            InsetList {
                if let heroAmount {
                    DappTransferHeroAmount(amount: heroAmount)
                }

                let combinedInfo = request.combinedInfo
                if combinedInfo.isDangerous {
                    SendDappWarningView()
                        .padding(.horizontal, 16)
                } else if combinedInfo.hasStateInit {
                    WarningView(text: lang("$signature_warning"), kind: .warning)
                        .padding(.horizontal, 16)
                }
                
                if request.shouldHideTransfers != true {
                    transfersSection
                }
                
                previewSection

                if request.isEmulationFeeInsufficient(accountContext: accountContext) {
                    WarningView(
                        text: L10n.dappInsufficientNetworkFeeWarning(token: operationChain.nativeToken.symbol),
                        kind: .warning
                    )
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 80)
            }
        }
    }
        
    private var transfersSection: some View {
        let addressNames = previewAddressNames
        return InsetSection {
            ForEach(sortedTransactions, id: \.self) { tx in
                TransferRow(
                    transfer: tx,
                    chain: operationChain,
                    accountContext: accountContext,
                    addressNames: addressNames,
                    action: onShowDetail
                )
            }
        } header: {
            Text(L10n.manyTransactions(count: transactionsCount))
        }
    }

    private var previewAddressNames: [String: String] {
        var names: [String: String] = [:]
        for activity in request.emulation?.activities ?? [] {
            guard let transaction = activity.transaction,
                  getChainBySlug(transaction.slug) == operationChain,
                  let name = transaction.metadata?.name?.nilIfEmpty,
                  let address = transaction.peerAddress?.nilIfEmpty else { continue }
            names[address] = name
            if let normalizedAddress = transaction.normalizedAddress?.nilIfEmpty {
                names[normalizedAddress] = name
            }
        }
        return names
    }
    
    @ViewBuilder
    private var previewSection: some View {
        if let emulation = request.emulation, !emulation.activities.isEmpty {
            let visibleActivities = emulation.activities.filter { $0.shouldHide != true }
            InsetSection {
                if visibleActivities.isEmpty && emulation.realFee == 0 {
                    Color.clear.frame(height: 0.1)
                }

                ForEach(visibleActivities) { activity in
                    WithPerceptionTracking {
                        WPreviewActivityCell(.init(activity: activity, accountContext: accountContext, tokenStore: tokenStore))
                    }
                }

                if emulation.realFee != 0 {
                    InsetCell {
                        FeeView(
                            token: operationChain.nativeToken,
                            nativeToken: operationChain.nativeToken,
                            fee: .init(
                                precision: .approximate,
                                terms: .init(token: nil, native: emulation.realFee, stars: nil),
                                nativeSum: emulation.realFee
                            ),
                            explainedTransferFee: nil,
                            includeLabel: true,
                            isError: request.isEmulationFeeInsufficient(accountContext: accountContext)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                let preview = Text(lang("Preview"))
                    .textStyle(.sectionHeader)
                let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                    .textStyle(.sectionHeader, content: .technical)
                    .foregroundColor(Color.orange)
                Text("\(preview) \(warning)")
                    .imageScale(.medium)
                    .overlay(alignment: .trailing) {
                        Button {
                            topWViewController()?.showTip(title: lang("Preview"), wide: false) {
                                Text(langMd("$preview_not_guaranteed"))
                                    .textStyle(.body, scaling: .dynamic)
                                    .multilineTextAlignment(.center)
                            }
                        } label: {
                            Color.clear.contentShape(.rect)
                        }
                        .frame(width: 44, height: 44)
                        .offset(x: 10)
                    }
                
            }
        } else {
            InsetSection {
                Text(lang("Preview is currently unavailable."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .textStyle(.footnote)
            }
        }
    }

    private func transactionSortCost(_ transaction: ApiDappTransfer) -> Double {
        let nativeToken = TokenStore.getNativeToken(chain: operationChain)
        let tonAmount = TokenAmount(transaction.amount + transaction.networkFee, nativeToken).doubleValue
        var cost = (nativeToken.priceUsd ?? 0) * tonAmount

        switch transaction.payload {
        case .tokensTransfer(let payload):
            if let token = TokenStore.getToken(slug: payload.slug) {
                cost += (token.priceUsd ?? 0) * TokenAmount(payload.amount, token).doubleValue
            }
        case .tokensTransferNonStandard(let payload):
            if let token = TokenStore.getToken(slug: payload.slug) {
                cost += (token.priceUsd ?? 0) * TokenAmount(payload.amount, token).doubleValue
            }
        case .nftTransfer:
            cost += 1_000_000_000
        default:
            break
        }

        return cost
    }
}

private struct SendDappPlaceholderView: View {
    var accountContext: AccountContext

    var body: some View {
        InsetList {
            InsetSection {
                InsetCell(horizontalPadding: 12) {
                    HStack(spacing: 12) {
                        PlaceholderCircleIcon()

                        PlaceholderTextColumn(
                            title: "12345 CUR",
                            subtitle: "Some target wallet address",
                            alignment: .leading
                        )
                    }
                }
            } header: {
                Text(L10n.manyTransactions(count: 1))
                   .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
            }
            
            InsetSection {
                InsetCell(horizontalPadding: 12) {
                    HStack(spacing: 12) {
                        PlaceholderCircleIcon()

                        PlaceholderTextColumn(
                            title: "An action",
                            subtitle: "Some wallet address",
                            alignment: .leading
                        )
                                                
                        PlaceholderTextColumn(
                            title: "12345 CUR",
                            subtitle: "Amount",
                            alignment: .trailing
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    
                    Text("Some fee: 11235 AMOUNT")
                        .textStyle(
                            .body,
                            content: .technical,
                            scaling: .dynamic
                        )
                        .lineSpacing(1)
                        .frame(minHeight: 22)
                        .skeletonPlaceholder(surface: .light)
                }
                
            } header: {
                Text(lang("Preview"))
                   .skeletonPlaceholder(surface: .dark, cornerRadius: 8)
            }
        }
        .skeletonContainer()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Button(action: {}) {
                    Text(lang("Cancel"))
                }
                .buttonStyle(.airSecondary)
                Button(action: {}) {
                    Text(lang("Send"))
                }
                .buttonStyle(.airPrimary)
            }
            .padding(16)
            .disabled(true)
        }
    }
}

private struct PlaceholderCircleIcon: View {
    var body: some View {
        Circle()
            .frame(width: 40, height: 40)
            .skeletonPlaceholder(surface: .light, cornerRadius: 20, cornerStyle: .circular)
    }
}

private struct PlaceholderTextColumn: View {
    var title: String
    var subtitle: String
    var alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title)
                .textStyle(.calloutEmphasized)
                .skeletonPlaceholder(surface: .light, barInset: .init(top: 0, leading: 0, bottom: 1, trailing: 0))
            Text(subtitle)
                .textStyle(.supporting)
                .lineSpacing(2)
                .padding(.top, 1)
                .skeletonPlaceholder(surface: .light, barInset: .init(top: 1, leading: 0, bottom: 0, trailing: 0))
        }
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview("Placeholder") {
    SendDappPlaceholderView(accountContext: AccountContext(source: .current))
        .background(Color.air.sheetBackground)
}
#endif
