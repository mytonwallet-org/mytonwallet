import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

private let debounceAddressResolution: Duration = .seconds(0.250)

enum AddressSource: Equatable {
    case constant(String)
    case myAccount(MAccount)
    case savedAccount(MAccount, saveKey: String)

    var isEmpty: Bool {
        .constant("") == self
    }
}

struct ResolvedAddress {
    var title: String?
    var address: String
    var domain: String?
}

enum AddressDisplayValue {
    case rawInput(String)
    case resolved(ResolvedAddress)
}

@Perceptible @MainActor
final class AddressInputModel {
        
    var textFieldInput: String = ""
    
    var isFocused: Bool = false
    
    var chain: ApiChain { token.chain }
    
    var source: AddressSource = .constant("")
    
    var onScanResult: (ScanResult) -> () = { _ in }
    
    @PerceptionIgnored
    @AccountContext var account: MAccount
    @PerceptionIgnored
    @TokenProvider var token: ApiToken
    @PerceptionIgnored
    var resolveAddressTask: Task<Void, any Error>?
    @PerceptionIgnored
    private var resolveObserver: ObserveToken?
    
    var isAddressLoading: Bool = false
    var addressInfos: [ApiChain: ApiGetAddressInfoResult]?
    
    private var inputObserver: ObserveToken?
    
    init(account: AccountContext, token: TokenProvider) {
        self._account = account
        self._token = token
        inputObserver = observe { [weak self] in
            guard let self else { return }
            let input = textFieldInput
            self.source = .constant(input)
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
    
    var resolvedAddress: ResolvedAddress? {
        switch source {
        case .myAccount(let account), .savedAccount(let account, _):
            if let accountChain = account.getChainInfo(chain: chain) {
                return ResolvedAddress(title: account.displayName, address: accountChain.address, domain: accountChain.domain)
            }
        case .constant:
            break
        }
        return nil
    }
    
    private func resolveAddress() {
        resolveAddressTask?.cancel()
        resolveAddressTask = Task {
            do {
                
                let compatibleChains = account.supportedChains.filter { $0.isValidAddressOrDomain(textFieldInput) }
                if compatibleChains.isEmpty {
                    addressInfos = nil
                }
                isAddressLoading = true
                try await Task.sleep(for: debounceAddressResolution)
                var infos: [ApiChain: ApiGetAddressInfoResult] = [:]
                for chain in compatibleChains {
                    infos[chain] = try await Api.getAddressInfo(chain: chain, network: account.network, address: textFieldInput)
                    try Task.checkCancellation()
                }
                self.addressInfos = infos
                isAddressLoading = false
            } catch {
                if !Task.isCancelled {
                    addressInfos = [:]
                    isAddressLoading = false
                }
            }
        }
    }
    
    var displayValue: AddressDisplayValue {
        if let resolvedAddress {
            .resolved(resolvedAddress)
        } else {
            .rawInput(textFieldInput)
        }
    }
    
    /// Value to use for backend validation/draft: user-entered address/domain, or account address for selected account.
    var draftAddressOrDomain: String {
        switch source {
        case .myAccount(let account), .savedAccount(let account, _):
            return account.getAddress(chain: chain) ?? textFieldInput
        case .constant(let raw):
            return raw
        }
    }
    
    // MARK: - Display helpers
    
    func displayComponents() -> (primary: String?, secondary: String?) {
        let chain = self.chain
        switch source {
        case .myAccount(let account), .savedAccount(let account, _):
            let title = account.displayName
            let address = account.getAddress(chain: chain)
            let formattedAddress = address.map { formatStartEndAddress($0) }
            return (title, formattedAddress)
            
        case .constant(let raw):
            let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { return (nil, nil) }
            
            let info = addressInfos?[chain]
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
