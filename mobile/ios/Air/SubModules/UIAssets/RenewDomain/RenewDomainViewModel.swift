import SwiftUI
import WalletContext
import WalletCore
import Perception
import Dependencies

struct RenewDomainDraftRequest: Equatable, Sendable {
    let accountId: String
    let nftAddresses: [String]
}

@Perceptible
@MainActor final class RenewDomainViewModel {

    let nftsToRenew: [String]

    @PerceptionIgnored
    @AccountContext var account: MAccount
    @PerceptionIgnored
    let draft: DraftEngine<RenewDomainDraftRequest, ApiDnsRenewalDraft>

    var isSubmitting = false

    var onRenew: (() -> Void)?

    init(accountSource: AccountSource, nftsToRenew: [String]) {
        let accountContext = AccountContext(source: accountSource)
        self._account = accountContext
        self.nftsToRenew = nftsToRenew
        self.draft = DraftEngine { request, _ in
            let nfts = request.nftAddresses.compactMap {
                accountContext.domains.nftsByAddress[$0]
            }
            return try await Api.checkDnsRenewalDraft(
                accountId: request.accountId,
                nfts: nfts
            )
        }
        draft.start { [weak self] in
            self?.draftRequest
        }
    }

    var nfts: [ApiNft] {
        let nftsByAddress = $account.domains.nftsByAddress
        return nftsToRenew.compactMap { nftsByAddress[$0] }
    }

    private var draftRequest: RenewDomainDraftRequest? {
        let nfts = nfts
        guard !nfts.isEmpty else { return nil }
        return RenewDomainDraftRequest(
            accountId: account.id,
            nftAddresses: nfts.map(\.address)
        )
    }

    var title: String {
        nftsToRenew.count > 1 ? lang("Renew Domains") : lang("Renew Domain")
    }

    var subtitle: String? {
        guard let date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) else { return nil }
        return L10n.untilDateCapitalized(date: date.formatted(.dateTime.year().month().day().locale(LocalizationSupport.shared.locale)))
    }

    var fee: MFee? {
        guard let realFee = draft.displayed?.realFee else { return nil }
        return MFee(
            precision: .exact,
            terms: .init(token: nil, native: realFee, stars: nil),
            nativeSum: realFee
        )
    }

    var errorMessage: String? {
        guard let failure = draft.failure else { return nil }
        return (failure as? LocalizedError)?.errorDescription
            ?? failure.localizedDescription
    }

    var isInsufficientBalance: Bool {
        guard let realFee = draft.displayed?.realFee else { return false }
        let tonBalance = $account.balances[TONCOIN_SLUG] ?? 0
        return tonBalance < realFee
    }

    var renewButtonTitle: String {
        if isInsufficientBalance {
            return lang("Insufficient Balance")
        }
        return nftsToRenew.count > 1 ? lang("Renew All") : lang("Renew")
    }

    var canRenew: Bool {
        !isSubmitting && draft.current != nil && !isInsufficientBalance
    }

    var isButtonLoading: Bool {
        isSubmitting || (draft.isLoading && !isInsufficientBalance)
    }

    func makeConfirmationSnapshot() -> RenewDomainConfirmationSnapshot? {
        guard canRenew, let current = draft.current else {
            return nil
        }
        let nfts = nfts
        guard !nfts.isEmpty else { return nil }
        return RenewDomainConfirmationSnapshot(
            account: account,
            nfts: nfts,
            realFee: current.draft.realFee
        )
    }
}
