import WalletCore

enum RecipientSuggestionStrategy: Equatable, Sendable {
    case all
    case preferActiveChain
    case requireActiveChain
}

enum SendRecipientPolicy: Equatable, Sendable {
    case flexibleChain(suggestions: RecipientSuggestionStrategy)
    case fixedChain(ApiChain)

    var suggestionStrategy: RecipientSuggestionStrategy {
        switch self {
        case .flexibleChain(let suggestions):
            suggestions
        case .fixedChain:
            .requireActiveChain
        }
    }

    func resolutionChains(
        from compatibleChains: [ApiChain]
    ) -> [ApiChain] {
        switch self {
        case .flexibleChain:
            return compatibleChains
        case .fixedChain(let chain):
            return compatibleChains.contains(chain) ? [chain] : []
        }
    }

    func shouldSelectChain(
        _ selectedChain: ApiChain,
        activeChain: ApiChain
    ) -> Bool {
        guard selectedChain != activeChain else {
            return false
        }
        if case .flexibleChain = self {
            return true
        }
        return false
    }

    func preferringActiveChain() -> SendRecipientPolicy {
        guard case .flexibleChain = self else { return self }
        return .flexibleChain(suggestions: .preferActiveChain)
    }

    func isRecipientCompatible(
        input: String,
        resolvedAddress: String?,
        senderAddress: String?,
        activeChain: ApiChain
    ) -> Bool {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return true }

        let address = resolvedAddress ?? input
        return activeChain.isValidAddressOrDomain(address)
            && (activeChain.isSendToSelfAllowed || address != senderAddress)
    }
}
