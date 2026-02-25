import Foundation
import WalletContext
import WalletCore
import Perception
import SwiftNavigation

@Perceptible
@MainActor final class LinkDomainViewModel {
    let nftAddress: String
    @PerceptionIgnored
    @AccountContext var account: MAccount

    @PerceptionIgnored
    private var resolveObserver: ObserveToken?
    @PerceptionIgnored
    private var resolveTask: Task<Void, any Error>?

    var walletAddress: String = ""
    var walletAddressName: String?
    var resolvedWalletAddress: String?
    var isAddressFocused = false

    var realFee: BigInt?
    var isLoadingDraft = false
    var isSubmitting = false
    var isResolvingAddress = false
    var errorMessage: String?

    var onLink: (() -> Void)?

    init(accountSource: AccountSource, nftAddress: String) {
        self._account = AccountContext(source: accountSource)
        self.nftAddress = nftAddress
        let linkedAddress = $account.domains.linkedAddressByAddress[nftAddress]?.nilIfEmpty
        self.walletAddress = linkedAddress ?? account.getAddress(chain: nft?.chain) ?? ""
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
        return !isSubmitting && !isLoadingDraft && realFee != nil && !isInsufficientBalance
    }

    private var normalizedWalletAddress: String {
        walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isButtonLoading: Bool {
        isSubmitting || isLoadingDraft
    }

    func displayComponents() -> (primary: String?, secondary: String?) {
        let input = normalizedWalletAddress
        guard !input.isEmpty else { return (nil, nil) }

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
        isLoadingDraft = true
        errorMessage = nil
        do {
            let address = account.getAddress(chain: nft.chain) ?? walletAddress
            let result = try await Api.checkDnsChangeWalletDraft(accountId: account.id, nft: nft, address: address)
            realFee = result.realFee
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            realFee = nil
        }
        isLoadingDraft = false
    }

    func submit(password: String?) async throws {
        guard !isSubmitting, let nft else { return }
        let address = normalizedWalletAddress
        guard !address.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let info = try await Api.getAddressInfo(chain: nft.chain, network: account.network, address: address)
        if let error = info.error?.nilIfEmpty {
            throw BridgeCallError(message: error, payload: nil)
        }
        let resolvedAddress = info.resolvedAddress?.nilIfEmpty ?? address
        let result = try await Api.submitDnsChangeWallet(
            accountId: account.id,
            password: password,
            nft: nft,
            address: resolvedAddress,
            realFee: realFee
        )
        _ = result
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
        guard !address.isEmpty else {
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
                    throw BridgeCallError(message: error, payload: nil)
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

}
