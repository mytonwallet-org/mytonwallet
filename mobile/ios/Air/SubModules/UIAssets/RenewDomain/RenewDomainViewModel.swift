import SwiftUI
import WalletContext
import WalletCore
import Perception
import Dependencies

@Perceptible
@MainActor final class RenewDomainViewModel {
    
    let nftsToRenew: [String]
    
    @PerceptionIgnored
    @AccountContext var account: MAccount

    var realFee: BigInt?
    var isLoadingDraft = false
    var isSubmitting = false
    var errorMessage: String?

    var onRenew: (() -> Void)?
    
    init(accountSource: AccountSource, nftsToRenew: [String]) {
        self._account = AccountContext(source: accountSource)
        self.nftsToRenew = nftsToRenew
    }

    var nfts: [ApiNft] {
        let nftsByAddress = $account.domains.nftsByAddress
        return nftsToRenew.compactMap { nftsByAddress[$0] }
    }
    
    var title: String {
        nftsToRenew.count > 1 ? lang("Renew Domains") : lang("Renew Domain")
    }
    
    var subtitle: String? {
        guard let date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) else { return nil }
        return lang("Until %date%", arg1: date.formatted(.dateTime.year().month().day().locale(LocalizationSupport.shared.locale)))
    }
    
    var fee: MFee? {
        guard let realFee else { return nil }
        return MFee(
            precision: .exact,
            terms: .init(token: nil, native: realFee, stars: nil),
            nativeSum: realFee
        )
    }
    
    var isInsufficientBalance: Bool {
        guard let realFee else { return false }
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
        !isSubmitting && !isLoadingDraft && realFee != nil && !isInsufficientBalance
    }
    
    var isButtonLoading: Bool {
        isSubmitting || isLoadingDraft
    }
    
    func loadDraft() async {
        guard !isLoadingDraft, !nfts.isEmpty else { return }
        isLoadingDraft = true
        errorMessage = nil
        do {
            let result = try await Api.checkDnsRenewalDraft(accountId: account.id, nfts: nfts)
            realFee = result.realFee
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            realFee = nil
        }
        isLoadingDraft = false
    }
    
    func submit(password: String?) async throws {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let result = try await Api.submitDnsRenewal(
            accountId: account.id,
            password: password,
            nfts: nfts,
            realFee: realFee
        )
        if let results = result as? [Any] {
            for entry in results {
                if let dict = entry as? [String: Any], let error = dict["error"] as? String {
                    throw BridgeCallError(message: error, payload: nil)
                }
            }
        }
    }
}
