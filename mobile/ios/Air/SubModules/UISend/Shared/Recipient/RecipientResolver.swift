import WalletContext
import WalletCore

enum RecipientSelection: Equatable, Sendable {
    case raw(String)
    case account(MAccount, fallbackChain: ApiChain)
    case savedAccount(MAccount, saveKey: String, fallbackChain: ApiChain)

    var isEmpty: Bool {
        self == .raw("")
    }

    var savedAddressKey: String? {
        guard case .savedAccount(_, let saveKey, _) = self else {
            return nil
        }
        return saveKey
    }

    func address(for chain: ApiChain) -> String {
        switch self {
        case .raw(let raw):
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .account(let account, let fallbackChain),
             .savedAccount(let account, _, let fallbackChain):
            return account.getAddress(chain: chain)
                ?? account.getAddress(chain: fallbackChain)
                ?? ""
        }
    }
}

struct RecipientResolutionRequest: Equatable, Hashable, Sendable {
    let network: ApiNetwork
    let input: String
    let chains: [ApiChain]
}

struct RecipientCandidate: Equatable, Sendable {
    let addressName: String?
    let resolvedAddress: String?

    init(
        addressName: String? = nil,
        resolvedAddress: String? = nil
    ) {
        self.addressName = addressName
        self.resolvedAddress = resolvedAddress
    }

    init(result: ApiGetAddressInfoResult) {
        self.init(
            addressName: result.addressName,
            resolvedAddress: result.resolvedAddress
        )
    }
}

struct RecipientResolverClient: Sendable {
    let resolve: @Sendable (
        _ request: RecipientResolutionRequest
    ) async throws -> [ApiChain: RecipientCandidate]
}

extension RecipientResolverClient {
    static let live = RecipientResolverClient { request in
        var candidates: [ApiChain: RecipientCandidate] = [:]
        for chain in request.chains {
            let result = try await Api.getAddressInfo(
                chain: chain,
                network: request.network,
                address: request.input
            )
            try Task.checkCancellation()
            candidates[chain] = RecipientCandidate(
                result: result
            )
        }
        return candidates
    }
}
