import WalletContext
import WalletCore

/// Everything a mint transfer needs, and the only place those numbers are decided.
///
/// It takes `FundableCardsInfo` rather than an `ApiCardsInfo`, so the debug promo preset cannot be
/// handed to it: the preset lives in `AccountConfig.cardsInfo`, which the sheet renders from, and
/// only WalletCore can produce the fundable copy. A refactor that reaches for the card property
/// nearest to hand gets a type error here rather than a transfer priced from invented numbers.
struct MintCardMintRequest: Equatable {
    let cardType: ApiMtwCardType
    let tokenAddress: String
    let amount: BigInt

    init?(cards: FundableCardsInfo, type: ApiMtwCardType, token: ApiToken?) {
        guard let cardInfo = cards[type],
              cardInfo.all > 0, cardInfo.notMinted > 0,
              cardInfo.price.isFinite, cardInfo.price > 0,
              let token, let tokenAddress = token.tokenAddress?.nilIfEmpty
        else { return nil }
        let amount = doubleToBigInt(cardInfo.price, decimals: token.decimals)
        guard amount > 0 else { return nil }
        self.cardType = type
        self.tokenAddress = tokenAddress
        self.amount = amount
    }
}
