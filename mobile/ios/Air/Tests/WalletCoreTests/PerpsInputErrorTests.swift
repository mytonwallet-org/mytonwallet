import Foundation
import Testing
import WalletContext
import WalletCore

struct PerpsInputErrorTests {
    @Test(arguments: [
        ("10.2", false, "10.2"), ("10.199", false, "10.2"),
        ("100.3", true, "100.31"), ("100.300001", true, "100.31"), ("0", false, "0"),
    ])
    func roundMinimumUpToAnEnterableAmount(minimum: String, isExclusive: Bool, expected: String) {
        let error = makeError("PerpsAmountTooSmall", details:
            #"{"minimumAmount":"\#(minimum)","isMinimumExclusive":\#(isExclusive)}"#)
        #expect(PerpsFormatting.error(error) == L10n.perpsMinimumAmount(amount: formatAmount(expected)))
    }

    @Test func distinguishReductionFromTotalAndPreserveSmallFees() {
        let reduction = makeError("PerpsAmountTooSmall", details: #"{"minimumReduction":"0.2"}"#)
        #expect(PerpsFormatting.error(reduction) == L10n.perpsMinimumReduction(amount: formatAmount("0.2")))
        let balance = makeError("PerpsInsufficientBalance", details: #"{"requiredBalance":"3.019","availableBalance":"0"}"#)
        #expect(PerpsFormatting.error(balance) == L10n.perpsRequiredBalance(required_: formatAmount("3.019"), available: "0"))
        let unknownFee = makeError("PerpsInsufficientBalance", details: #"{"availableBalance":"2"}"#)
        #expect(PerpsFormatting.error(unknownFee) == L10n.perpsAvailableBalance(available: "2"))
    }

    @Test(arguments: ["-1", "NaN", "10garbage", "1.2.3", "", "١٠"])
    func fallBackForInvalidAmountMetadata(amount: String) {
        let error = makeError("PerpsAmountTooSmall", details: #"{"minimumAmount":"\#(amount)"}"#)
        #expect(PerpsFormatting.error(error) == lang("PerpsAmountTooSmall"))
    }

    @Test func keepLegacyAndUnrelatedErrorsReadable() {
        #expect(PerpsFormatting.error(makeError("PerpsAmountTooSmall", details: "{}")) == lang("PerpsAmountTooSmall"))
        #expect(PerpsFormatting.error(makeError("PerpsAmountTooSmall", details: #"{"minimumAmount":10}"#)) == lang("PerpsAmountTooSmall"))
        #expect(PerpsFormatting.error(makeError("PerpsPositionChanged", details: #"{"minimumAmount":"10"}"#)) == lang("PerpsPositionChanged"))
        #expect(PerpsFormatting.error(SdkError.apiReturnedError(error: "PerpsInsufficientBalance", data: nil)) == lang("PerpsInsufficientBalance"))
    }

    private func makeError(_ code: String, details: String) -> SdkError {
        .javaScriptException(.init(methodName: "perpsPreviewOrder",
            exceptionMessage: #"{"message":"\#(code)","name":"Error","additionalData":\#(details)}"#))
    }

    private func formatAmount(_ value: String) -> String {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
            .formatted(.number.locale(.forNumberFormatters).precision(.fractionLength(0...6)))
    }
}
