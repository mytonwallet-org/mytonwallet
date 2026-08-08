import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

private let debounceAddressResolution: Duration = .seconds(0.250)

enum SendRecipientValidationState: Equatable {
    case invalid
    case incompatible

    var localizationKey: String {
        switch self {
        case .invalid:
            "$send_recipient_invalid"
        case .incompatible:
            "$send_recipient_not_compatible"
        }
    }

    static func evaluate(
        input: String,
        isFocused: Bool,
        activeChain: ApiChain,
        senderAddress: String?,
        validatedRecipient: SendValidatedRecipient?,
        showsIncompatibleError: Bool
    ) -> SendRecipientValidationState? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isFocused else { return nil }

        let validChains = ApiChain.allCases.filter {
            $0.isValidAddressOrDomain(input)
        }
        guard !validChains.isEmpty else { return .invalid }
        guard validChains.contains(activeChain) else {
            return showsIncompatibleError ? .incompatible : nil
        }

        let address = validatedRecipient?.resolvedAddress ?? input
        if isSendAddressDraftError(validatedRecipient?.error)
            || (!activeChain.isSendToSelfAllowed
                && address == senderAddress) {
            return .invalid
        }
        return nil
    }
}

@Perceptible @MainActor
final class SendRecipientModel {

    var textFieldInput: String = ""

    var isFocused: Bool = false

    private(set) var chain: ApiChain

    private(set) var recipientPolicy: SendRecipientPolicy

    private var selection: RecipientSelection = .raw("")

    var onScanResult: (ScanResult) -> () = { _ in }
    var onSuggestionChainSelected: (ApiChain) -> () = { _ in }
    var onCompatibleChainDetected: (ApiChain) -> () = { _ in }

    @PerceptionIgnored
    @AccountContext var account: MAccount
    @PerceptionIgnored
    private var resolveAddressTask: Task<Void, Never>?
    @PerceptionIgnored
    private let resolver: RecipientResolverClient
    @PerceptionIgnored
    private var resolutionRevision: UInt64 = 0
    @PerceptionIgnored
    private var loadingResolutionRequest: RecipientResolutionRequest?
    @PerceptionIgnored
    private var resolveObserver: ObserveToken?
    @PerceptionIgnored
    private var synchronizedSelectionInput: String?

    private var addressCandidates: [ApiChain: RecipientCandidate]?

    private var inputObserver: ObserveToken?

    private var normalizedTextFieldInput: String {
        textFieldInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        account: AccountContext,
        chain: ApiChain,
        recipientPolicy: SendRecipientPolicy =
            .flexibleChain(suggestions: .all),
        resolver: RecipientResolverClient = .live
    ) {
        self._account = account
        self.chain = chain
        self.recipientPolicy = recipientPolicy
        self.resolver = resolver
        inputObserver = observe { [weak self] in
            guard let self else { return }
            let input = textFieldInput
            guard input != synchronizedSelectionInput else {
                return
            }
            synchronizedSelectionInput = nil
            self.selection = .raw(input)
        }
        resolveObserver = observe { [weak self] in
            guard let self else { return }
            _ = (self.account.id, self.textFieldInput)
            self.resolveAddress()
        }
    }

    deinit {
        resolveAddressTask?.cancel()
    }

    private func resolveAddress() {
        let input = normalizedTextFieldInput
        guard !input.isEmpty else {
            resetResolution()
            return
        }
        let compatibleChains = ApiChain.allCases.filter {
            account.supportedChains.contains($0) && $0.isValidAddressOrDomain(input)
        }
        let resolutionChains = recipientPolicy.resolutionChains(
            from: compatibleChains
        )
        guard !resolutionChains.isEmpty else {
            resetResolution()
            return
        }
        let request = RecipientResolutionRequest(
            network: account.network,
            input: input,
            chains: resolutionChains
        )
        guard loadingResolutionRequest != request else {
            return
        }

        resolutionRevision &+= 1
        let revision = resolutionRevision
        loadingResolutionRequest = request
        addressCandidates = nil
        resolveAddressTask?.cancel()
        if request.chains.count == 1,
           let chain = request.chains.first {
            onCompatibleChainDetected(chain)
        }
        let resolver = self.resolver
        resolveAddressTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounceAddressResolution)
                let candidates = try await resolver.resolve(request)
                try Task.checkCancellation()
                guard let self else { return }
                guard resolutionRevision == revision,
                      loadingResolutionRequest == request else {
                    return
                }
                addressCandidates = candidates
                loadingResolutionRequest = nil
            } catch {
                guard let self, !Task.isCancelled else { return }
                guard resolutionRevision == revision,
                      loadingResolutionRequest == request else {
                    return
                }
                addressCandidates = [:]
                loadingResolutionRequest = nil
            }
        }
    }

    private func resetResolution() {
        resolutionRevision &+= 1
        resolveAddressTask?.cancel()
        resolveAddressTask = nil
        loadingResolutionRequest = nil
        addressCandidates = nil
    }

    var isEmpty: Bool {
        normalizedTextFieldInput.isEmpty
    }

    /// Value to use for backend validation/draft: user-entered address/domain, or account address for selected account.
    var draftAddressOrDomain: String {
        selection.address(for: chain)
    }

    func makeAddressViewModel(
        validatedRecipient: SendValidatedRecipient?
    ) -> AddressViewModel {
        let apiName = validatedRecipient?.addressName
        let saveKey: String? = switch selection {
        case .savedAccount:
            selection.savedAddressKey
        case .account:
            nil
        case .raw:
            if let apiName, chain.isValidDomain(apiName) {
                apiName
            } else {
                nil
            }
        }

        return AddressViewModel(
            chain: chain,
            apiAddress: validatedRecipient?.resolvedAddress,
            apiName: apiName,
            saveKey: saveKey
        )
    }

    func updateChain(_ chain: ApiChain) {
        guard self.chain != chain else { return }
        self.chain = chain
        synchronizeTextFieldWithSelection()
        resolveAddress()
    }

    func preferActiveChainSuggestions() {
        recipientPolicy = recipientPolicy.preferringActiveChain()
    }

    func clear() {
        synchronizedSelectionInput = nil
        selection = .raw("")
        textFieldInput = ""
    }

    func selectSavedAccount(
        _ account: MAccount,
        saveKey: String,
        fallbackChain: ApiChain
    ) {
        setSelection(.savedAccount(
            account,
            saveKey: saveKey,
            fallbackChain: fallbackChain
        ))
        didSelectSuggestion(chain: fallbackChain)
    }

    func selectAccount(
        _ account: MAccount,
        fallbackChain: ApiChain
    ) {
        setSelection(.account(
            account,
            fallbackChain: fallbackChain
        ))
        didSelectSuggestion(chain: fallbackChain)
    }

    private func setSelection(_ selection: RecipientSelection) {
        self.selection = selection
        synchronizeTextFieldWithSelection()
    }

    private func synchronizeTextFieldWithSelection() {
        guard case .raw = selection else {
            let input = selection.address(for: chain)
            synchronizedSelectionInput = input
            textFieldInput = input
            return
        }
    }

    func isCompatible(resolvedAddress: String?) -> Bool {
        recipientPolicy.isRecipientCompatible(
            input: draftAddressOrDomain,
            resolvedAddress: resolvedAddress,
            senderAddress: account.getAddress(chain: chain),
            activeChain: chain
        )
    }

    func validationState(
        validatedRecipient: SendValidatedRecipient?,
        showsIncompatibleError: Bool
    ) -> SendRecipientValidationState? {
        SendRecipientValidationState.evaluate(
            input: draftAddressOrDomain,
            isFocused: isFocused,
            activeChain: chain,
            senderAddress: account.getAddress(chain: chain),
            validatedRecipient: validatedRecipient,
            showsIncompatibleError: showsIncompatibleError
        )
    }

    func shouldShowDomainScamWarning(
        draftError: ApiAnyDisplayError?
    ) -> Bool {
        guard draftError != .domainNotResolved else { return false }
        guard case .raw(let input) = selection else { return false }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.firstMatch(of: DOMAIN_SCAM_REGEX) != nil
    }

    func didSelectSuggestion(chain selectedChain: ApiChain) {
        guard recipientPolicy.shouldSelectChain(
            selectedChain,
            activeChain: chain
        ) else {
            return
        }
        onSuggestionChainSelected(selectedChain)
    }

    // MARK: - Display helpers

    func displayComponents() -> (primary: String?, secondary: String?) {
        let chain = self.chain
        switch selection {
        case .account(let account, let fallbackChain), .savedAccount(let account, _, let fallbackChain):
            let title = account.displayName
            let address = account.getAddress(chain: chain) ?? account.getAddress(chain: fallbackChain)
            let formattedAddress = address.map { formatStartEndAddress($0) }
            return (title, formattedAddress)

        case .raw(let raw):
            let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { return (nil, nil) }

            let info = addressCandidates?[chain]
            let resolvedAddress = info?.resolvedAddress?.nilIfEmpty
            let addressName = info?.addressName?.nilIfEmpty

            if let resolvedAddress {

                if let addressName { // show domain/name + resolved address
                    return (addressName, formatStartEndAddress(resolvedAddress))
                }

                if resolvedAddress != input {
                    // user entered domain, show domain + resolved address
                    return (input, formatStartEndAddress(resolvedAddress))
                }

                // resolved matches input (plain address)
                return (resolvedAddress, nil)
            } else {
                // no resolution yet, show raw input (formatted if looks like address)
                return (input, nil)
            }
        }
    }
}
