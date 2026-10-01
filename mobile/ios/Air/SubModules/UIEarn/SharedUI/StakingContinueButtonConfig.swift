import UIComponents
import WalletContext
import WalletCore

extension DraftButtonConfiguration {
    static func staking(title: String, phase: OperationDraftPhase, canRetry: Bool, draftError: ApiAnyDisplayError?) -> Self {
        if let draftError {
            return .init(title: .text(draftError.toLocalized), isEnabled: false, showLoading: false)
        }
        return .init(
            title: .text(phase == .failed ? lang("Retry") : title),
            isEnabled: phase == .ready || (phase == .failed && canRetry),
            showLoading: phase == .loading
        )
    }

    static func insufficientStakingFee(minAmount: BigInt) -> Self {
        .init(
            title: .text(L10n.insufficientFee(fee: "\(minAmount.doubleAbsRepresentation(decimals: 9)) GRAM")),
            isEnabled: false,
            showLoading: false
        )
    }
}
