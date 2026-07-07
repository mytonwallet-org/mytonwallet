import Foundation
import WalletContext
import WalletCore
import Perception
import SwiftNavigation

@Perceptible
@MainActor final class LinkDomainViewModel {
    let nftAddress: String
    let initialNft: ApiNft?
    @PerceptionIgnored
    @AccountContext var account: MAccount

    @PerceptionIgnored
    private var resolveObserver: ObserveToken?
    @PerceptionIgnored
    private var resolveTask: Task<Void, any Error>?

    var walletAddress: String = ""
    var selectedWalletAccount: MAccount?
    var walletAddressName: String?
    var resolvedWalletAddress: String?
    var isAddressFocused = false

    var realFee: BigInt?
    var isLoadingDraft = false
    var isSubmitting = false
    var isResolvingAddress = false
    var errorMessage: String?

    var onLink: (() -> Void)?

    init(accountSource: AccountSource, nftAddress: String, nft: ApiNft? = nil) {
        self._account = AccountContext(source: accountSource)
        self.nftAddress = nftAddress
        self.initialNft = nft
        let linkedAddress = $account.domains.linkedAddressByAddress[nftAddress]?.nilIfEmpty
        self.walletAddress = linkedAddress ?? account.getAddress(chain: nft?.chain) ?? ""
        self.selectedWalletAccount = matchingImportedWallet(for: self.walletAddress, chain: nft?.chain)
        resolveObserver = observe { [weak self] in
            guard let self else { return }
            _ = (self.walletAddress, self.account.network)
            self.resolveAddress()
        }
    }

    deinit {
        resolveTask?.cancel()
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

    var fee: MFee? {
        guard let realFee else { return nil }
        return MFee(
            precision: .exact,
            terms: .init(token: nil, native: realFee, stars: nil),
            nativeSum: realFee
        )
    }

    var isAddressValid: Bool {
        let value = normalizedWalletAddress
        guard !value.isEmpty, let chain = nft?.chain else { return false }
        return chain.isValidAddressOrDomain(value)
    }

    var isInsufficientBalance: Bool {
        guard let realFee else { return false }
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
        guard isAddressValid else { return false }
        if let linkedWalletAddress, linkedWalletAddress == normalizedWalletAddress { return false }
        return !isSubmitting && !isInsufficientBalance
    }

    private var normalizedWalletAddress: String {
        walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isButtonLoading: Bool {
        isSubmitting || isLoadingDraft || realFee == nil
    }

    func displayComponents() -> (primary: String?, secondary: String?) {
        let input = normalizedWalletAddress
        guard !input.isEmpty else { return (nil, nil) }

        if let selectedWalletAccount, let chain = nft?.chain, importedWallet(selectedWalletAccount, matches: input, chain: chain) {
            return (selectedWalletAccount.displayName, formatStartEndAddress(selectedWalletAccount.getAddress(chain: chain) ?? input))
        }

        let resolved = resolvedWalletAddress?.nilIfEmpty
        let name = walletAddressName?.nilIfEmpty

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

    func loadDraft() async {
        guard !isLoadingDraft, let nft else { return }
        setInitialWalletAddressIfNeeded(for: nft)
        isLoadingDraft = true
        errorMessage = nil
        do {
            let address = normalizedWalletAddress.nilIfEmpty ?? account.getAddress(chain: nft.chain) ?? ""
            let result = try await Api.checkDnsChangeWalletDraft(accountId: account.id, nft: nft, address: address)
            realFee = result.realFee
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            realFee = nil
        }
        isLoadingDraft = false
    }

    func selectWalletAccount(_ account: MAccount) {
        guard let chain = nft?.chain, let address = account.getAddress(chain: chain) else { return }
        selectedWalletAccount = account
        walletAddress = address
    }

    func submit(password: String?) async throws -> ApiMfaProtectedResult {
        guard !isSubmitting, let nft else { return ApiMfaProtectedResult() }
        isSubmitting = true
        defer { isSubmitting = false }
        let resolvedAddress = try await resolvedSubmissionAddress(for: nft)
        let result = try await Api.submitDnsChangeWallet(
            accountId: account.id,
            password: password,
            nft: nft,
            address: resolvedAddress,
            realFee: realFee
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return ApiMfaProtectedResult(
            activityId: result.activityId,
            mfaRequestHash: result.mfaRequestHash
        )
    }

    func makeLedgerPayload() async throws -> SignData {
        guard let nft else { throw CancellationError() }
        let resolvedAddress = try await resolvedSubmissionAddress(for: nft)
        return .linkDomain(
            accountId: account.id,
            nft: nft,
            address: resolvedAddress,
            realFee: realFee
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

    private func resolveAddress() {
        resolveTask?.cancel()
        let address = normalizedWalletAddress
        selectedWalletAccount = matchingImportedWallet(for: address, chain: nft?.chain)
        guard !address.isEmpty else {
            walletAddressName = nil
            resolvedWalletAddress = nil
            isResolvingAddress = false
            return
        }
        if selectedWalletAccount != nil {
            walletAddressName = nil
            resolvedWalletAddress = nil
            isResolvingAddress = false
            return
        }
        guard let chain = nft?.chain, chain.isValidAddressOrDomain(address) else {
            walletAddressName = nil
            resolvedWalletAddress = nil
            isResolvingAddress = false
            return
        }
        isResolvingAddress = true
        resolveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let info = try await Api.getAddressInfo(chain: chain, network: account.network, address: address)
                if let error = info.error?.nilIfEmpty {
                    throw SdkError.apiReturnedError(error: error, context: nil)
                }
                walletAddressName = info.addressName
                resolvedWalletAddress = info.resolvedAddress
                isResolvingAddress = false
            } catch {
                if !Task.isCancelled {
                    walletAddressName = nil
                    resolvedWalletAddress = nil
                    isResolvingAddress = false
                }
            }
        }
    }

    private func setInitialWalletAddressIfNeeded(for nft: ApiNft) {
        guard normalizedWalletAddress.isEmpty else {
            selectedWalletAccount = matchingImportedWallet(for: normalizedWalletAddress, chain: nft.chain)
            return
        }
        walletAddress = linkedWalletAddress ?? account.getAddress(chain: nft.chain) ?? ""
        selectedWalletAccount = matchingImportedWallet(for: walletAddress, chain: nft.chain)
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

    private func resolvedSubmissionAddress(for nft: ApiNft) async throws -> String {
        let address = normalizedWalletAddress
        guard !address.isEmpty else { throw SdkError.message(.invalidAddress) }
        let info = try await Api.getAddressInfo(chain: nft.chain, network: account.network, address: address)
        if let error = info.error?.nilIfEmpty {
            throw SdkError.apiReturnedError(error: error, context: nil)
        }
        return info.resolvedAddress?.nilIfEmpty ?? address
    }

}
