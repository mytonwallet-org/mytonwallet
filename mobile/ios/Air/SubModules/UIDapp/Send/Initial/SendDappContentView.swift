
import SwiftUI
import UIKit
import UIPasscode
import UIActivityList
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

enum SendDappViewOrPlaceholderContent {
    case placeholder(TonConnectPlaceholder)
    case sendDapp(SendDappContentView)
}

struct SendDappViewOrPlaceholder: View {
    
    var content: SendDappViewOrPlaceholderContent
    
    var body: some View {
        switch content {
        case .placeholder(let view):
            view
                .transition(.opacity.animation(.default))
        case .sendDapp(let view):
            view
                .transition(.opacity.animation(.default))
        }
    }
}

struct SendDappContentView: View {
    
    var accountContext: AccountContext
    var request: ApiUpdate.DappSendTransactions
    var operationChain: ApiChain
    var onShowDetail: (ApiDappTransfer) -> ()
    
    var transactionsCount: Int { request.transactions.count }
    var hasAmount: Bool { request.combinedInfo.nftsCount > 0 || !request.combinedInfo.tokenTotals.isEmpty }
    var headerTokenDisplay: ApiUpdate.DappSendTransactions.TokenDisplayInfo { request.tokenToDisplay(accountContext: accountContext) }
    var sortedTransactions: [ApiDappTransfer] {
        request.transactions.sorted { lhs, rhs in
            transactionSortCost(lhs) > transactionSortCost(rhs)
        }
    }
    
    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            InsetList {
                DappHeaderView(
                    dapp: request.dapp,
                    accountContext: accountContext,
                    customTokenBalance: headerTokenDisplay.balance,
                    customToken: headerTokenDisplay.token
                )
                
                if request.combinedInfo.isDangerous {
                    SendDappWarningView()
                        .padding(.horizontal, 16)
                }
                
                totalAmountSection

                if request.shouldHideTransfers != true {
                    transfersSection
                }
                
                previewSection
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 80)
            }
        }
    }
    
    @ViewBuilder
    var totalAmountSection: some View {
        if transactionsCount > 1 && hasAmount {
            InsetSection {
                TotalAmountRow(info: request.combinedInfo)
                    .padding(.vertical, -1)
            } header: {
                Text(lang("Total Amount"))
            }
        }
    }
    
    var transfersSection: some View {
        InsetSection {
            ForEach(sortedTransactions, id: \.self) { tx in
                TransferRow(transfer: tx, chain: operationChain, action: onShowDetail)
            }
        } header: {
            Text(lang("$many_transactions", arg1: transactionsCount))
        }
    }
    
    @ViewBuilder
    var previewSection: some View {
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
                            includeLabel: true
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                let preview = Text(lang("Preview"))
                let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                    .foregroundColor(Color.orange)
                Text("\(preview) \(warning)")
                    .imageScale(.medium)
                    .overlay(alignment: .trailing) {
                        Button {
                            topWViewController()?.showTip(title: lang("Preview"), wide: false) {
                                Text(langMd("$preview_not_guaranteed"))
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
                    .font(.system(size: 13))
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
