import Foundation
import WalletContext
import WalletCore

enum SendRoute: Equatable, Sendable {
    case tokenCompose(TokenSendConfiguration)
    case tokenReview(TokenSendConfiguration)
    case nftCompose(NftSendConfiguration)
    case nftReview(NftSendConfiguration)

    init(prefilledValues: SendPrefilledValues) throws {
        if prefilledValues.mode.isNftRelated
            || prefilledValues.nfts?.isEmpty == false {
            let configuration = try NftSendConfiguration(
                prefilledValues: prefilledValues
            )
            self = configuration.mode == .burn
                ? .nftReview(configuration)
                : .nftCompose(configuration)
        } else {
            let configuration = TokenSendConfiguration(
                prefilledValues: prefilledValues
            )
            self = configuration.mode == .sellToMoonpay
                ? .tokenReview(configuration)
                : .tokenCompose(configuration)
        }
    }
}

enum SendRouteError: Error, Equatable, LocalizedError {
    case missingNfts
    case mixedNftChains

    var errorDescription: String? {
        switch self {
        case .missingNfts:
            lang("No NFT selected")
        case .mixedNftChains:
            lang("Selected NFTs must use the same network")
        }
    }
}

private extension TokenSendConfiguration {
    init(prefilledValues: SendPrefilledValues) {
        self.init(
            mode: prefilledValues.mode == .sellToMoonpay
                ? .sellToMoonpay
                : .send,
            initialAddress: prefilledValues.address,
            initialAmount: prefilledValues.amount,
            initialTokenSlug: prefilledValues.token?.nilIfEmpty,
            jettonAddress: prefilledValues.jetton?.nilIfEmpty,
            initialComment: prefilledValues.commentOrMemo ?? "",
            binaryPayload: prefilledValues.binaryPayload?.nilIfEmpty,
            stateInit: prefilledValues.stateInit
        )
    }
}

private extension NftSendConfiguration {
    init(prefilledValues: SendPrefilledValues) throws {
        guard let nfts = prefilledValues.nfts, !nfts.isEmpty else {
            throw SendRouteError.missingNfts
        }
        let chain = nfts[0].chain
        guard nfts.allSatisfy({ $0.chain == chain }) else {
            throw SendRouteError.mixedNftChains
        }
        self.init(
            mode: prefilledValues.mode == .burnNft ? .burn : .send,
            initialAddress: prefilledValues.address,
            nfts: nfts,
            chain: chain,
            initialComment: prefilledValues.commentOrMemo ?? ""
        )
    }
}
