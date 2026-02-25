
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher
import Dependencies
import Perception

struct ActivityView: View {

    var model: ActivityDetailsViewModel
    var onDecryptComment: () -> ()
    var onTokenTapped: ((ApiToken) -> Void)?
    var decryptedComment: String?
    var isSensitiveDataHidden: Bool

    @Namespace private var ns
    
    @State private var detailsOpacity: CGFloat = 0

    @State private var collapsedHeight: CGFloat = 0
    @State private var detailsHeight: CGFloat = 0

    var activity: ApiActivity { model.activity }
    var neverUseProgressiveExpand: Bool {
        if let comment = activity.transaction?.comment {
            return activity.transaction?.nft != nil && comment.count > 20
        }
        return false
    }
    
    @Dependency(\.tokenStore) private var tokens
    
    var token: ApiToken? { tokens[activity.slug] }

    private var chain: ApiChain {
        token?.chain ?? FALLBACK_CHAIN
    }

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetList(spacing: 16) {
                
                VStack(spacing: 20) {
                    if activity.transaction?.nft != nil {
                        nftHeader
                    } else {
                        header
                            .padding(.horizontal, 16)
                    }
                    
                    commentSection
                    
                    encryptedCommentSection
                    
                    actionsRow
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(ns)).height }, action: { maxY in
                    model.collapsedHeight = maxY + 24
                    model.onHeightChange()
                })
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }, action: { maxY in
                    let y = maxY - screenHeight + 32.0
                    detailsOpacity = clamp(-y / 70, to: 0...1)
                })
                .padding(.bottom, -8)
                
                transactionDetailsSection
                
                Color.clear.frame(width: 0, height: 0)
                    .padding(.bottom, 34 - 16)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(ns)).maxY }, action: { maxY in
                        model.expandedHeight = maxY
                        model.onHeightChange()
                    })
            }
            .environment(\.insetListContext, .elevated)
            .coordinateSpace(name: ns)
            .animation(.default, value: activity)
            .animation(.default, value: decryptedComment)
            .scrollDisabled(model.scrollingDisabled)
            .backportScrollClipDisabled()
        }
    }

    @ViewBuilder
    var nftHeader: some View {
        if let tx = activity.transaction, let nft = tx.nft {
            VStack(alignment: .leading, spacing: 0) {
                NftImage(nft: nft, animateIfPossible: true, loadFullSize: true)
                    .padding(.bottom, 12)
                let name: String = if let _name = nft.name, let idx = nft.index, idx > 0 {
                    "\(_name)"
                } else {
                    nft.name ?? "NFT"
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.system(size: 24, weight: .semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text((tx.isIncoming == true ? lang("Received from") : lang("Sent to")) + " ")
                        TappableAddress(
                            account: model.accountContext,
                            model: .fromTransaction(tx, chain: chain, addressKind: .peer),
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color(WTheme.groupedItem))
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    var header: some View {
        switch activity {
        case .transaction(let tx):
            if let token {
                TransactionActivityHeader(
                    account: model.accountContext,
                    transaction: tx,
                    token: token,
                    amountDisplayMode: activity.amountDisplayMode,
                    onTokenTapped: onTokenTapped,
                    isTransactionConfirmation: model.context.isTransactionConfirmation,
                )
            }
        case .swap(let swap):
            if let fromAmount = swap.fromAmountInt64, let toAmount = swap.toAmountInt64, let fromToken = swap.fromToken, let toToken = swap.toToken {
                SwapOverviewView(
                    fromAmount: TokenAmount(fromAmount, fromToken),
                    toAmount: TokenAmount(toAmount, toToken),
                    onTokenTapped: onTokenTapped
                )
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    var commentSection: some View {
        if let comment = activity.transaction?.comment {
            SBubbleView(content: .comment(comment), direction: activity.transaction?.isIncoming == true ? .incoming : .outgoing, isError: activity.transaction?.status == .failed)
                .padding(.horizontal, 44)
        }
    }

    @ViewBuilder
    var encryptedCommentSection: some View {
        
        let canDecrypt = AccountStore.account?.type == .mnemonic
        
        if activity.transaction?.encryptedComment != nil {
            if let decryptedComment {
                SBubbleView(content: .comment(decryptedComment), direction: activity.transaction?.isIncoming == true ? .incoming : .outgoing, isError: activity.transaction?.status == .failed)
                    .padding(.horizontal, 44)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else {
                Button(action: onDecryptComment) {
                    VStack(spacing: 0) {
                        SBubbleView(content: .encryptedComment, direction: activity.transaction?.isIncoming == true ? .incoming : .outgoing, isError: activity.transaction?.status == .failed)
                            .padding(.horizontal, 44)
                        if canDecrypt {
                            Text(lang("Tap to reveal"))
                                .font(.system(size: 10))
                                .foregroundStyle(Color(WTheme.secondaryLabel))
                        }
                    }
                    .contentShape(.rect)
                }
                .allowsHitTesting(canDecrypt)
                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.7))))
            }
        }
    }

    var actionsRow: some View {
        ActionsRow(model: model)
    }
    
    @ViewBuilder
    var transactionDetailsSection: some View {
        Group {
            if model.context == .external {
                senderAddress
                recipientAddress
            } else {
                peerAddress
            }
            InsetSection {
                nftCollection
                if activity.transaction?.nft == nil {
                    amountCell
                }
                changellyAddress
                swapRate
                fee
                transactionId
                changellyId
            } header: {
                Text(lang("Details"))
                    .padding(.bottom, 1)
            }
            .padding(.bottom, 5 + 16)
            .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(model.progressiveRevealEnabled && !neverUseProgressiveExpand ? detailsOpacity : model.detailsExpanded ? 1 : 0)
        .animation(.spring, value: model.detailsExpanded)
    }
    
    @ViewBuilder
    private func addressSection(activity: ApiActivity, address: ApiTransactionActivity.AddressKind, title: String) -> some View {
        if case .transaction(let tx) = activity, nil != tx.getAddress(for: address) {
            let chain = getChainBySlug(tx.slug) ?? FALLBACK_CHAIN
            InsetSection {
                InsetCell {
                    TappableAddressFull(accountContext: model.accountContext, model: .fromTransaction(tx, chain: chain, addressKind: address))
                }
            } header: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    var senderAddress: some View {
        addressSection(activity: activity, address: .from, title: lang("Sender"))
    }

    @ViewBuilder
    var recipientAddress: some View {
        addressSection(activity: activity, address: .to, title: lang("Recipient"))
    }

    @ViewBuilder
    var peerAddress: some View {
        if case .transaction(let tx) = activity {
           addressSection(activity: activity, address: .peer, title: tx.isIncoming ? lang("Sender") : lang("Recipient"))
        }
    }

    @ViewBuilder
    var nftCollection: some View {
        if let nft = activity.transaction?.nft {
            InsetDetailCell {
                Text(lang("Collection"))
                    .font17h22()
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                if let name = nft.collectionName?.nilIfEmpty, let _ = nft.collectionAddress {
                    Button(action: onNftCollectionTap) {
                        Text(name)
                            .foregroundStyle(Color(WTheme.tint))
                            .font17h22()
                    }
                } else {
                    Text(lang("Standalone NFT"))
                        .font17h22()
                }
            }
        }
    }

    func onNftCollectionTap() {
        if let accountId = AccountStore.accountId, let nft = activity.transaction?.nft, let name = nft.collectionName?.nilIfEmpty, let address = nft.collectionAddress {
            if NftStore.accountOwnsCollection(accountId: accountId, address: address, chain: nft.chain) {
                AppActions.showAssets(accountSource: .accountId(accountId), selectedTab: 1, collectionsFilter: .collection(.init(chain: nft.chain, address: address, name: name)))
            } else {
                AppActions.openInBrowser(ExplorerHelper.nftCollectionUrl(nft))
            }
        }
    }

    @ViewBuilder
    var changellyAddress: some View {
        if let swap = activity.swap, swap.fromToken?.isOnChain == false, let payinAddress = swap.cex?.payinAddress.nilIfEmpty {
            InsetDetailCell {
                Text(lang("Changelly Payment Address"))
                    .font17h22()
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                Text(formatAddressAttributed(payinAddress, startEnd: true))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    var amountCell: some View {
        if let transaction = activity.transaction, let token {
            InsetDetailCell {
                Text(lang("Amount"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                let amount = TokenAmount(transaction.amount, token)
                let inToken = amount
                    .formatted(.none, showMinus: false)
                let curr = TokenStore.baseCurrency
                let token = TokenStore.getToken(slug: activity.slug)
                Text(token?.price != nil ? "\(inToken) (\(amount.convertTo(curr, exchangeRate: token!.price!).formatted(.baseCurrencyEquivalent, showMinus: false)))" : inToken)
                    .sensitiveDataInPlace(cols: 10, rows: 2, cellSize: 9, theme: .adaptive, cornerRadius: 5)
            }
        }
    }

    @ViewBuilder
    var swapRate: some View {
        if let swap = activity.swap, let ex = ExchangeRateHelpers.getSwapRate(fromAmount: swap.fromAmount.value, toAmount: swap.toAmount.value, fromToken: swap.fromToken, toToken: swap.toToken) {
            InsetDetailCell {
                Text(lang("Exchange Rate"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                let exchangeAmount = TokenAmount.fromDouble(ex.price, ex.fromToken)
                let exchangeRateString = exchangeAmount.formatted(.compact,
                    roundUp: false,
                    precision: swap.status == .pending || swap.status == .pendingTrusted ? .approximate : .exact
                )
                Text("\(ex.toToken.symbol) ≈ \(exchangeRateString)")
            }
        }
    }

    private func _computeDisplayFee(nativeToken: ApiToken) -> MFee? {
        switch activity {
        case .transaction(let transaction):
            let fee = transaction.fee
            if fee > 0 {
                return MFee(precision: .exact, terms: .init(token: nil, native: fee, stars: nil), nativeSum: nil)
            }
        case .swap(let swap):
            if let native = (swap.networkFee?.value).flatMap({ doubleToBigInt($0, decimals: ApiToken.TONCOIN.decimals) }) {
                let token = TokenStore.tokens[swap.from] ?? .TONCOIN
                let ourFee = (swap.ourFee?.value).flatMap {
                    doubleToBigInt($0, decimals: token.decimals)
                }
                if native <= 0, (ourFee ?? 0) <= 0 {
                    return nil
                }
                let fromToncoin = swap.from == TONCOIN_SLUG
                let terms: MFee.FeeTerms = .init(
                    token: fromToncoin ? nil : ourFee,
                    native: fromToncoin ? native + (ourFee ?? 0) : native,
                    stars: nil
                )

                let fee = MFee(
                    precision: swap.status == .pending || swap.status == .pendingTrusted ? .approximate : .exact,
                    terms: terms,
                    nativeSum: nil
                )
                return fee
            }
        }
        return nil
    }

    @ViewBuilder
    var fee: some View {
        if let token {
            let chain = token.chain
            if chain.isSupported, let fee = _computeDisplayFee(nativeToken: chain.nativeToken) {
                InsetDetailCell {
                    Text(lang("Fee"))
                        .foregroundStyle(Color(WTheme.secondaryLabel))
                } value: {
                    FeeView(
                        token: token,
                        nativeToken: chain.nativeToken,
                        fee: fee,
                        explainedTransferFee: nil,
                        includeLabel: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    var transactionId: some View {
        let txId = activity.parsedTxId.hash
        if !activity.isBackendSwapId && txId.count > 20 {
            InsetDetailCell {
                Text(lang("Transaction ID"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .fixedSize()
            } value: {
                TappableTransactionId(chain: self.chain, txId: txId)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    var changellyId: some View {
        if let id = activity.swap?.cex?.transactionId {
            InsetDetailCell {
                Text("Changelly ID")
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .fixedSize()
            } value: {
                ChangellyTransactionId(id: id)
                    .fixedSize()
            }
        }
    }
}
