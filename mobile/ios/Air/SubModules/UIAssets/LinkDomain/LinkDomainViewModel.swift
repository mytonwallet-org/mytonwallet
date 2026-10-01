import Foundation
import WalletContext
import WalletCore
import Perception
import SwiftNavigation

struct LinkDomainDraftRequest: Equatable, Sendable {
    let accountId: String
    let nftAddress: String
    let walletAddress: String
}

/// Resolution and fee for one (domain, destination address) pair, loaded
/// as a single draft so display and confirmation read the same values.
struct LinkDomainValidatedDraft: Sendable {
    let realFee: BigInt
    let resolvedAddress: String
    let addressName: String?
}

@Perceptible
@MainActor final class LinkDomainViewModel {
    let nftAddress: String
    let initialNft: ApiNft?
    @PerceptionIgnored
    @AccountContext var account: MAccount
    @PerceptionIgnored
    let draft: DraftEngine<LinkDomainDraftRequest, LinkDomainValidatedDraft>
    @PerceptionIgnored
    private var initialAddressObserver: ObserveToken?
    @PerceptionIgnored
    private var didFillInitialWalletAddress = false

    var walletAddress: String = ""
    var isAddressFocused = false
    var isSubmitting = false

    var onLink: (() -> Void)?

    init(accountSource: AccountSource, nftAddress: String, nft: ApiNft? = nil) {
        let accountContext = AccountContext(source: accountSource)
        self._account = accountContext
        self.nftAddress = nftAddress
        self.initialNft = nft
        let initialNft = nft
        self.draft = DraftEngine(
            debounce: { from, to in
                // Typed address transitions debounce; the first request and
                // account changes load immediately.
                guard let from,
                      from.accountId == to.accountId,
                      from.nftAddress == to.nftAddress else {
                    return .zero
                }
                return .milliseconds(250)
            },
            sameScope: {
                // The fee keeps showing while the address is retyped.
                $0.accountId == $1.accountId
                    && $0.nftAddress == $1.nftAddress
            },
            load: { request, _ in
                let nft = accountContext.domains.nftsByAddress[request.nftAddress]
                    ?? initialNft
                    ?? NftStore.getNft(accountId: request.accountId, nftId: request.nftAddress)?.nft
                guard let nft else {
                    throw DisplayError(text: lang("Unexpected error"))
                }
                let info = try await Api.getAddressInfo(
                    chain: nft.chain,
                    network: accountContext.account.network,
                    address: request.walletAddress
                )
                if let error = info.error?.nilIfEmpty {
                    throw SdkError.apiReturnedError(error: error, context: nil)
                }
                let resolvedAddress = info.resolvedAddress?.nilIfEmpty
                    ?? request.walletAddress
                // The fee emulation builds the same change message as the
                // submission, which requires a parseable blockchain
                // address — never a domain name.
                let feeDraft = try await Api.checkDnsChangeWalletDraft(
                    accountId: request.accountId,
                    nft: nft,
                    address: resolvedAddress
                )
                return LinkDomainValidatedDraft(
                    realFee: feeDraft.realFee,
                    resolvedAddress: resolvedAddress,
                    addressName: info.addressName?.nilIfEmpty
                )
            }
        )

        let linkedAddress = accountContext.domains.linkedAddressByAddress[nftAddress]?.nilIfEmpty
        self.walletAddress = linkedAddress
            ?? accountContext.account.getAddress(chain: nft?.chain)
            ?? ""
        if walletAddress.isEmpty {
            // The chain is unknown until the NFT arrives; fill the default
            // destination once it does, without ever overriding a field
            // the user has touched or cleared.
            initialAddressObserver = observe { [weak self] in
                guard let self else { return }
                fillInitialWalletAddressIfNeeded()
            }
        } else {
            didFillInitialWalletAddress = true
        }
        draft.start { [weak self] in
            self?.draftRequest
        }
    }

    var title: String {
        linkedWalletAddress == nil ? lang("Link to Wallet") : lang("Change Linked Wallet")
    }

    var addressLabel: String {
        linkedWalletAddress == nil ? lang("Wallet") : lang("Linked Wallet")
    }

    var nft: ApiNft? {
        $account.domains.nftsByAddress[nftAddress]
            ?? initialNft
            ?? NftStore.getNft(accountId: account.id, nftId: nftAddress)?.nft
    }

    var linkedWalletAddress: String? {
        $account.domains.linkedAddressByAddress[nftAddress]?.nilIfEmpty
    }

    private var draftRequest: LinkDomainDraftRequest? {
        let address = normalizedWalletAddress
        guard let chain = nft?.chain,
              !address.isEmpty,
              chain.isValidAddressOrDomain(address) else {
            return nil
        }
        return LinkDomainDraftRequest(
            accountId: account.id,
            nftAddress: nftAddress,
            walletAddress: address
        )
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

    var isAddressValid: Bool {
        let value = normalizedWalletAddress
        guard !value.isEmpty, let chain = nft?.chain else { return false }
        return chain.isValidAddressOrDomain(value)
    }

    var isInsufficientBalance: Bool {
        guard let realFee = draft.displayed?.realFee else { return false }
        let tonBalance = $account.balances[TONCOIN_SLUG] ?? 0
        return tonBalance < realFee
    }

    var linkButtonTitle: String {
        if isInsufficientBalance {
            return lang("Insufficient Balance")
        }
        return lang("Link")
    }

    var canLink: Bool {
        guard !isSubmitting, isAddressValid else { return false }
        if let linkedWalletAddress, linkedWalletAddress == normalizedWalletAddress { return false }
        return draft.current != nil && !isInsufficientBalance
    }

    var selectedWalletAccount: MAccount? {
        matchingImportedWallet(for: normalizedWalletAddress, chain: nft?.chain)
    }

    private var normalizedWalletAddress: String {
        walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isButtonLoading: Bool {
        if isSubmitting { return true }
        guard !isInsufficientBalance else { return false }
        if nft == nil { return true }
        guard isAddressValid, normalizedWalletAddress != linkedWalletAddress else { return false }
        return draft.isLoading
    }

    func displayComponents() -> (primary: String?, secondary: String?) {
        let input = normalizedWalletAddress
        guard !input.isEmpty else { return (nil, nil) }

        if let selectedWalletAccount, let chain = nft?.chain, importedWallet(selectedWalletAccount, matches: input, chain: chain) {
            return (selectedWalletAccount.displayName, formatStartEndAddress(selectedWalletAccount.getAddress(chain: chain) ?? input))
        }

        // Resolution shows only for the exact live request — never a stale
        // answer for a previous input.
        let resolved = draft.current?.draft.resolvedAddress
        let name = draft.current?.draft.addressName

        if let resolved {
            if let name {
                return (name, formatStartEndAddress(resolved))
            }
            if resolved != input {
                return (input, formatStartEndAddress(resolved))
            }
            return (resolved, nil)
        }

        return (input, nil)
    }

    func selectWalletAccount(_ account: MAccount) {
        guard let chain = nft?.chain, let address = account.getAddress(chain: chain) else { return }
        walletAddress = address
    }

    func makeConfirmationSnapshot() -> LinkDomainConfirmationSnapshot? {
        guard canLink, let nft, let current = draft.current else {
            return nil
        }
        let inputAddress = current.request.walletAddress
        let resolvedAddress = current.draft.resolvedAddress
        let destinationName: String?
        if let selectedWalletAccount,
           importedWallet(selectedWalletAccount, matches: inputAddress, chain: nft.chain) {
            destinationName = selectedWalletAccount.displayName
        } else if let name = current.draft.addressName {
            destinationName = name
        } else if resolvedAddress != inputAddress {
            destinationName = inputAddress
        } else {
            destinationName = nil
        }
        return LinkDomainConfirmationSnapshot(
            account: account,
            nft: nft,
            destinationAddress: resolvedAddress,
            destinationName: destinationName,
            realFee: current.draft.realFee
        )
    }

    func applyScanResult(_ result: ScanResult) {
        switch result {
        case .url(let url):
            if let parsed = parseTonTransferUrl(url) {
                walletAddress = parsed.address
            }
        case .address(let address, let possibleChains):
            if let chain = nft?.chain, possibleChains.contains(chain) {
                walletAddress = address
            }
        }
    }

    private func fillInitialWalletAddressIfNeeded() {
        guard !didFillInitialWalletAddress else { return }
        guard normalizedWalletAddress.isEmpty else {
            didFillInitialWalletAddress = true
            initialAddressObserver = nil
            return
        }
        guard let nft else { return }
        didFillInitialWalletAddress = true
        initialAddressObserver = nil
        walletAddress = linkedWalletAddress
            ?? account.getAddress(chain: nft.chain)
            ?? ""
    }

    private func matchingImportedWallet(for value: String, chain: ApiChain?) -> MAccount? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chain, !value.isEmpty else { return nil }
        let accountsById = AccountStore.accountsById
        return AccountStore.orderedAccountIds.compactMap { accountsById[$0] }.first { account in
            account.network == self.account.network && importedWallet(account, matches: value, chain: chain)
        }
    }

    private func importedWallet(_ account: MAccount, matches value: String, chain: ApiChain) -> Bool {
        guard let chainInfo = account.getChainInfo(chain: chain) else { return false }
        if chainInfo.address == value { return true }
        if chainInfo.domain?.caseInsensitiveCompare(value) == .orderedSame { return true }
        return false
    }

}
