
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
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
    @State private var scrollToTopTrigger: UUID? = nil

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
            InsetList(spacing: 16, scrollToTopTrigger: scrollToTopTrigger) {
                
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
                .onGeometryChange(for: CGFloat.self, of: { [ns] in $0.frame(in: .named(ns)).height }, action: { maxY in
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
                    .onGeometryChange(for: CGFloat.self, of: { [ns] in $0.frame(in: .named(ns)).maxY }, action: { maxY in
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
            .onChange(of: model.detailsExpanded) { expanded in
                if !expanded {
                    scrollToTopTrigger = UUID()
                }
            }
        }
    }

    @ViewBuilder
    var nftHeader: some View {
        if let tx = activity.transaction, let activityNft = tx.nft {
            let nft = nftWithStoredTelegramGiftLottie(activityNft)
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { proxy in
                    NftMedia(
                        nft: nft,
                        playAnimationOnce: true,
                        mediaContentMode: .scaleAspectFill,
                        animationRenderingConfiguration: .nftDetailsHeaderDefault
                    )
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipped()
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.bottom, 12)
                .onTapGesture { showNft(nft, isExpanded: true) }
                let name: String = if let _name = nft.name, let idx = nft.index, idx > 0 {
                    "\(_name)"
                } else {
                    nft.name ?? "NFT"
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.system(size: 24, weight: .semibold))
                        .onTapGesture { showNft(nft, isExpanded: false) }
                    if activity.shouldShowTransactionAddress(in: .details) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text((tx.isIncoming == true ? lang("Received from") : lang("Sent to")) + " ")
                                .font17h22()
                            TappableAddress(
                                account: model.accountContext,
                                model: .fromTransaction(tx, chain: chain, addressKind: .peer),
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color.air.groupedItem)
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func nftWithStoredTelegramGiftLottie(_ nft: ApiNft) -> ApiNft {
        NftStore.nftWithStoredTelegramGiftLottie(accountId: model.accountContext.accountId, nft: nft)
    }
    
    private func showNft(_ nft: ApiNft, isExpanded: Bool) {
        AppActions.showNft(accountContext: model.accountContext, nft: nft, isExpanded: isExpanded)
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
            SwapOverviewView(
                fromAmount: swap.displayFromAmount,
                toAmount: swap.displayToAmount,
                onTokenTapped: onTokenTapped
            )
            .padding(.top, 16)
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
        
        let canDecrypt = model.accountContext.account.type == .mnemonic
        
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
                                .foregroundStyle(Color.air.secondaryLabel)
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
                cexPaymentAddress
                swapRate
                fee
                swapTransactionIds
                transactionId
                swapProviderId
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
        if case .transaction(let tx) = activity,
           nil != tx.getAddress(for: address),
           address == .from || activity.shouldShowTransactionAddress(in: .details) {
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
                    .foregroundStyle(Color.air.secondaryLabel)
            } value: {
                if let name = nft.collectionName?.nilIfEmpty, let _ = nft.collectionAddress {
                    Button(action: onNftCollectionTap) {
                        Text(name)
                            .foregroundStyle(.tint)
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
        let accountContext = model.accountContext
        let accountId = accountContext.accountId
        if let nft = activity.transaction?.nft, let name = nft.collectionName?.nilIfEmpty, let address = nft.collectionAddress {
            if NftStore.accountOwnsCollection(accountId: accountId, address: address, chain: nft.chain) {
                let collectionFilter = NftCollectionFilter.collection(.init(chain: nft.chain, address: address, name: name))
                AppActions.showAssets(
                    accountSource: accountContext.source,
                    selectedTab: .nftCollectionFilter(collectionFilter),
                    collectionsFilter: collectionFilter
                )
            } else {
                AppActions.openInBrowser(ExplorerHelper.nftCollectionUrl(nft))
            }
        }
    }

    @ViewBuilder
    var cexPaymentAddress: some View {
        if let swap = activity.swap,
           let cex = swap.cex,
           let fromToken = swap.fromToken,
           !fromToken.isOnChain,
           let payinAddress = cex.payinAddress.nilIfEmpty {
            InsetDetailCell {
                Text(lang("Payment Address"))
                    .font17h22()
                    .foregroundStyle(Color.air.secondaryLabel)
            } value: {
                CopyableAddressText(
                    address: payinAddress,
                    copyToastMessage: lang("%chain% Address Copied", arg1: fromToken.chain.title)
                )
            }
        }
    }

    @ViewBuilder
    var amountCell: some View {
        if let transaction = activity.transaction, let token {
            InsetDetailCell {
                Text(lang("Amount"))
                    .foregroundStyle(Color.air.secondaryLabel)
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
                    .foregroundStyle(Color.air.secondaryLabel)
            } value: {
                let exchangeAmount = TokenAmount.fromDouble(ex.price, ex.fromToken)
                let exchangeRateString = exchangeAmount.formatted(.compact,
                    roundHalfUp: false,
                    precision: swap.displayStatus().isPending ? .approximate : .exact
                )
                Text("\(ex.toToken.symbol) = \(exchangeRateString)")
            }
        }
    }

    private func _computeDisplayFee(nativeToken: ApiToken) -> MFee? {
        switch activity {
        case .transaction(let transaction):
            let fee = transaction.fee
            if fee > 0 {
                return MFee(
                    precision: getIsActivityPendingForUser(activity) ? .approximate : .exact,
                    terms: .init(token: nil, native: fee, stars: nil),
                    nativeSum: nil
                )
            }
        case .swap(let swap):
            if let native = (swap.networkFee?.value).flatMap({ doubleToBigInt($0, decimals: nativeToken.decimals) }) {
                let token = TokenStore.tokens[swap.from] ?? nativeToken
                let ourFee = swap.ourFeeMode == "included" ? nil : (swap.ourFee?.value).flatMap {
                    doubleToBigInt($0, decimals: token.decimals)
                }
                if native <= 0, (ourFee ?? 0) <= 0 {
                    return nil
                }
                let fromNative = token.isNative
                let terms: MFee.FeeTerms = .init(
                    token: fromNative ? nil : ourFee,
                    native: fromNative ? native + (ourFee ?? 0) : native,
                    stars: nil
                )

                let fee = MFee(
                    precision: swap.displayStatus().isPending ? .approximate : .exact,
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
            let isLoading = model.isLoadingDetails
            let fee = _computeDisplayFee(nativeToken: chain.nativeToken)
            if chain.isSupported, isLoading || fee != nil {
                InsetDetailCell {
                    Text(lang("Fee"))
                        .foregroundStyle(Color.air.secondaryLabel)
                } value: {
                    FeeView(
                        token: token,
                        nativeToken: chain.nativeToken,
                        fee: fee,
                        explainedTransferFee: nil,
                        includeLabel: false,
                        isLoading: isLoading
                    )
                }
            }
        }
    }


    @ViewBuilder
    var swapTransactionIds: some View {
        if let swap = activity.swap {
            let outgoing = swap.transactionIds.outgoing
            let incoming = swap.transactionIds.incoming
            if let outgoing, let incoming, outgoing.hash != incoming.hash {
                swapTransactionIdCell(label: lang("Outgoing Transaction ID"), transactionId: outgoing)
                swapTransactionIdCell(label: lang("Incoming Transaction ID"), transactionId: incoming)
            } else if let transactionId = outgoing ?? incoming {
                swapTransactionIdCell(label: lang("Transaction ID"), transactionId: transactionId)
            }
        }
    }

    @ViewBuilder
    private func swapTransactionIdCell(label: String, transactionId: ApiSwapTransactionRef) -> some View {
        InsetDetailCell {
            Text(label)
                .foregroundStyle(Color.air.secondaryLabel)
                .fixedSize()
        } value: {
            TappableTransactionId(chain: transactionId.chain, txId: transactionId.hash)
                .fixedSize()
        }
    }

    @ViewBuilder
    var transactionId: some View {
        let txId = activity.parsedTxId.hash
        if !activity.isBackendSwapId && txId.count > 20 {
            InsetDetailCell {
                Text(lang("Transaction ID"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .fixedSize()
            } value: {
                TappableTransactionId(chain: self.chain, txId: txId)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    var swapProviderId: some View {
        if let swap = activity.swap,
           let cex = swap.cex,
           let transactionId = cex.transactionId.nilIfEmpty {
            let providerName = cex.providerName?.nilIfEmpty
            InsetDetailCell {
                Text(providerName.map { lang("Swap ID for %provider%", arg1: $0) } ?? lang("Swap ID"))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            } value: {
                SwapProviderTransactionId(
                    id: transactionId,
                    trackingUrl: swapProviderTrackingUrl(swap: swap, transactionId: transactionId)
                )
                    .fixedSize()
            }
        }
    }

    private func swapProviderTrackingUrl(swap: ApiSwapActivity, transactionId: String) -> URL? {
        guard swap.cexLabel.isChangellyOrLegacy,
              let encodedId = transactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://changelly.com/track/\(encodedId)")
    }

}
