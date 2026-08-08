import Testing
@testable import UISend
import WalletContext
import WalletCore

@Suite("Send Balance Policy")
struct SendBalancePolicyTests {
    @Test
    func `amount above token balance is classified separately`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            nativeTokenBalance: 100,
            transferAmount: 101,
            fullFee: nil,
            canTransferFullBalance: false,
            draftError: nil
        )

        #expect(status == .insufficientAmount)
    }

    @Test
    func `native fee is checked for a non-native token`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            nativeTokenBalance: 4,
            transferAmount: 100,
            fullFee: fee(token: nil, native: 5),
            canTransferFullBalance: false,
            draftError: nil
        )

        #expect(status == .insufficientFee)
    }

    @Test
    func `token diesel is checked in addition to transfer amount`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            nativeTokenBalance: 0,
            transferAmount: 96,
            fullFee: fee(token: 5, native: nil),
            canTransferFullBalance: false,
            draftError: nil
        )

        #expect(status == .insufficientFee)
    }

    @Test
    func `full native balance is allowed when the chain deducts the fee`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: TONCOIN_SLUG,
            nativeTokenBalance: 100,
            transferAmount: 100,
            fullFee: fee(token: nil, native: 5),
            canTransferFullBalance: true,
            draftError: nil
        )

        #expect(status == .sufficient)
    }

    @Test
    func `native amount and fee are checked against the same balance`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: TONCOIN_SLUG,
            nativeTokenBalance: 100,
            transferAmount: 96,
            fullFee: fee(token: nil, native: 5),
            canTransferFullBalance: false,
            draftError: nil
        )

        #expect(status == .insufficientFee)
    }

    @Test
    func `SDK insufficient balance blocks both token and NFT drafts`() {
        let tokenStatus = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            nativeTokenBalance: 100,
            transferAmount: 10,
            fullFee: nil,
            canTransferFullBalance: false,
            draftError: .insufficientBalance
        )
        let nftStatus = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: TONCOIN_SLUG,
            nativeTokenBalance: 100,
            transferAmount: 0,
            fullFee: nil,
            canTransferFullBalance: false,
            draftError: .insufficientBalance
        )

        #expect(tokenStatus == .insufficientFee)
        #expect(nftStatus == .insufficientFee)
    }

    @Test
    func `missing fee stays provisionally sufficient`() {
        let status = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            nativeTokenBalance: 0,
            transferAmount: 100,
            fullFee: nil,
            canTransferFullBalance: false,
            draftError: nil
        )

        #expect(status == .sufficient)
    }

    @Test
    func `available diesel covers the quoted native equivalent`() {
        let explainedFee = makeExplainedFee(
            isGasless: true,
            canTransferFullBalance: false,
            token: 4,
            native: 0,
            nativeSum: 5
        )
        let diesel = TokenSendDieselQuote(
            status: .available,
            tokenAmount: 4,
            transaction: nil
        )

        let evaluation = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            isNativeToken: false,
            nativeTokenBalance: 0,
            transferAmount: 96,
            displayedFee: explainedFee,
            computationalFee: explainedFee,
            displayedDiesel: diesel,
            computationalDiesel: diesel,
            draftError: nil
        )

        #expect(evaluation.status == .sufficient)
        #expect(!evaluation.shouldShowFullFee)
    }

    @Test
    func `displayed and computational fees are evaluated separately`() {
        let displayedFee = makeExplainedFee(
            isGasless: false,
            canTransferFullBalance: false,
            token: nil,
            native: 5,
            nativeSum: 5
        )
        let computationalFee = makeExplainedFee(
            isGasless: true,
            canTransferFullBalance: false,
            token: 4,
            native: 0,
            nativeSum: 5
        )
        let diesel = TokenSendDieselQuote(
            status: .available,
            tokenAmount: 4,
            transaction: nil
        )

        let evaluation = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            isNativeToken: false,
            nativeTokenBalance: 0,
            transferAmount: 96,
            displayedFee: displayedFee,
            computationalFee: computationalFee,
            displayedDiesel: nil,
            computationalDiesel: diesel,
            draftError: nil
        )

        #expect(evaluation.status == .sufficient)
        #expect(evaluation.shouldShowFullFee)
    }

    @Test
    func `full native transfer requires fee below the balance`() {
        let explainedFee = makeExplainedFee(
            isGasless: false,
            canTransferFullBalance: true,
            token: nil,
            native: 100,
            nativeSum: 100
        )

        let evaluation = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: TONCOIN_SLUG,
            isNativeToken: true,
            nativeTokenBalance: 100,
            transferAmount: 100,
            displayedFee: explainedFee,
            computationalFee: explainedFee,
            displayedDiesel: nil,
            computationalDiesel: nil,
            draftError: nil
        )

        #expect(evaluation.status == .insufficientFee)
        #expect(evaluation.shouldShowFullFee)
    }

    @Test
    func `stars diesel does not consume the transferred token`() {
        let explainedFee = makeExplainedFee(
            isGasless: true,
            canTransferFullBalance: false,
            token: nil,
            native: 0,
            nativeSum: 5,
            stars: 1
        )
        let diesel = TokenSendDieselQuote(
            status: .starsFee,
            tokenAmount: nil,
            transaction: nil
        )

        let evaluation = SendBalancePolicy.evaluate(
            tokenBalance: 100,
            tokenSlug: "jetton",
            isNativeToken: false,
            nativeTokenBalance: 0,
            transferAmount: 100,
            displayedFee: explainedFee,
            computationalFee: explainedFee,
            displayedDiesel: diesel,
            computationalDiesel: diesel,
            draftError: nil
        )

        #expect(evaluation.status == .sufficient)
        #expect(!evaluation.shouldShowFullFee)
    }
}

private func fee(
    token: BigInt?,
    native: BigInt?
) -> MFee.FeeTerms {
    .init(token: token, native: native, stars: nil)
}

private func makeExplainedFee(
    isGasless: Bool,
    canTransferFullBalance: Bool,
    token: BigInt?,
    native: BigInt?,
    nativeSum: BigInt?,
    stars: BigInt? = nil
) -> ExplainedTransferFee {
    let fee = MFee(
        precision: .exact,
        terms: .init(
            token: token,
            native: native,
            stars: stars
        ),
        nativeSum: nativeSum
    )
    return ExplainedTransferFee(
        isGasless: isGasless,
        canTransferFullBalance: canTransferFullBalance,
        fullFee: fee,
        realFee: fee
    )
}
