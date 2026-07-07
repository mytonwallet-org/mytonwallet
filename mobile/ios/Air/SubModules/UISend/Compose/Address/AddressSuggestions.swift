import WalletContext
import WalletCore
import SwiftUI
import ContextMenuKit
import Dependencies
import UIComponents
import Perception

struct AddressSuggestions: View {

    let model: AddressInputModel

    @Dependency(\.accountStore) var accountStore

    private var searchString: String {
        model.textFieldInput.lowercased()
    }

    private var addresses: [SavedAddressSuggestion] {
        let suggestions = model.$account.savedAddresses.getMatching(searchString)
            .map { savedAddress in
                SavedAddressSuggestion(
                    savedAddress: savedAddress,
                    isCompatibleWithToken: savedAddress.chain == model.chain
                )
            }

        switch model.suggestionChainMode {
        case .all:
            return suggestions
        case .requireCurrentTokenChain:
            return suggestions.filter(\.isCompatibleWithToken)
        case .preferCurrentTokenChain:
            return suggestions.sortedByCompatibility
        }
    }

    private var matchingAccounts: [AccountSuggestion] {
        let isEmpty = searchString.isEmpty
        let regex = Regex<Substring>(verbatim: searchString).ignoresCase()
        let network = model.account.network
        let otherAccountIds = accountStore.orderedAccountIds
            .filter { $0 != model.account.id }
        let accountsById = accountStore.accountsById
        let suggestions = otherAccountIds
            .compactMap { accountId -> AccountSuggestion? in
                guard let account = accountsById[accountId] else { return nil }
                guard account.network == network else { return nil }
                guard isEmpty || account.matches(regex) else { return nil }

                let isCompatible = account.supports(chain: model.chain)
                if model.suggestionChainMode == .requireCurrentTokenChain, !isCompatible {
                    return nil
                }

                return AccountSuggestion(
                    accountId: accountId,
                    selectedChain: isCompatible ? model.chain : account.firstChain,
                    isCompatibleWithToken: isCompatible
                )
            }

        switch model.suggestionChainMode {
        case .all, .requireCurrentTokenChain:
            return suggestions
        case .preferCurrentTokenChain:
            return suggestions.sortedByCompatibility
        }
    }

    var body: some View {
        WithPerceptionTracking {
            savedAddressesSection
            myAccountsSection
        }
    }

    @ViewBuilder
    private var savedAddressesSection: some View {
        if !addresses.isEmpty {
            InsetSection {
                ForEach(addresses, id: \.savedAddress) { suggestion in
                    let account = makeTemporaryAccount(saved: suggestion.savedAddress)
                    SavedAddressButton(
                        model: model,
                        suggestion: suggestion,
                        accountContext: model.$account,
                        account: AccountContext(source: .constant(account))
                    )
                }
            } header: {
                Text(lang("$saved_addresses_header"))
            }
        }
    }

    @ViewBuilder
    private var myAccountsSection: some View {
        if !matchingAccounts.isEmpty {
            InsetSection {
                ForEach(matchingAccounts, id: \.accountId) { suggestion in
                    AccountButton(model: model, suggestion: suggestion, account: AccountContext(accountId: suggestion.accountId))
                }
            } header: {
                Text(lang("My"))
            }
        }
    }

    private func makeTemporaryAccount(saved: SavedAddress) -> MAccount {
        let byChain: [ApiChain: AccountChain] = [saved.chain: AccountChain(address: saved.address)]
        return MAccount(id: saved.address + "-mainnet", title: saved.name, type: .view, byChain: byChain, isTemporary: true)
    }
}

private struct SavedAddressSuggestion: Hashable {
    let savedAddress: SavedAddress
    let isCompatibleWithToken: Bool
}

private struct AccountSuggestion: Hashable {
    let accountId: String
    let selectedChain: ApiChain
    let isCompatibleWithToken: Bool
}

private extension Array where Element == SavedAddressSuggestion {
    var sortedByCompatibility: [SavedAddressSuggestion] {
        filter(\.isCompatibleWithToken) + filter { !$0.isCompatibleWithToken }
    }
}

private extension Array where Element == AccountSuggestion {
    var sortedByCompatibility: [AccountSuggestion] {
        filter(\.isCompatibleWithToken) + filter { !$0.isCompatibleWithToken }
    }
}

private struct SavedAddressButton: View {

    let model: AddressInputModel
    var suggestion: SavedAddressSuggestion
    var accountContext: AccountContext
    @State var account: AccountContext

    private var savedAddress: SavedAddress {
        suggestion.savedAddress
    }

    private var incompatibilityText: String? {
        guard model.suggestionChainMode == .preferCurrentTokenChain, !suggestion.isCompatibleWithToken else {
            return nil
        }
        return lang("$address_suggestion_no_chain", arg1: model.chain.title)
    }

    var body: some View {
        if IOS_26_MODE_ENABLED {
            _content
        } else {
            _content
                .contextMenu {
                    Button(role: .destructive) {
                        accountContext.savedAddresses.delete(savedAddress)
                    } label: {
                        Label(lang("Remove"), systemImage: "trash")
                    }
                }
        }
    }
    
    var _content: some View {
        InsetButtonCell(horizontalPadding: 0, verticalPadding: 0, action: onTap) {
            AccountListCell(
                accountContext: account,
                isReordering: false,
                showCurrentAccountHighlight: false,
                addressLineSuffix: incompatibilityText,
                isDimmed: incompatibilityText != nil
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contextMenuSource(
                    triggers: IOS_26_MODE_ENABLED ? [.longPress] : [],
                    sourcePortal: ContextMenuSourcePortal(
                        mask: .roundedAttachmentRect(cornerRadius: S.insetSectionCornerRadius, cornerCurve: .continuous),
                        showsBackdropCutout: true
                    )
                ) {
                    makeMenuConfiguration()
                }
        }
    }
    
    func onTap() {
        model.source = .savedAccount(account.wrappedValue, saveKey: savedAddress.address, fallbackChain: savedAddress.chain)
        model.didSelectSuggestion(chain: savedAddress.chain)
        endEditing()
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Remove"),
                        icon: .system("trash"),
                        role: .destructive,
                        handler: {
                            withAnimation {
                                accountContext.savedAddresses.delete(savedAddress)
                            }
                        }
                    )
                )
            ]),
            backdrop: .dimmed(alpha: 0.18),
            style: ContextMenuStyle(minWidth: 180.0)
        )
    }
}

private struct AccountButton: View {
    
    let model: AddressInputModel
    let suggestion: AccountSuggestion
    @State var account: AccountContext

    private var incompatibilityText: String? {
        guard model.suggestionChainMode == .preferCurrentTokenChain, !suggestion.isCompatibleWithToken else {
            return nil
        }
        return lang("$address_suggestion_no_chain", arg1: model.chain.title)
    }
    
    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: onTap) {
            AccountListCell(
                accountContext: account,
                isReordering: false,
                showCurrentAccountHighlight: false,
                addressLineSuffix: incompatibilityText,
                isDimmed: incompatibilityText != nil
            )
        }
    }
    
    func onTap() {
        model.source = .myAccount(account.wrappedValue, fallbackChain: suggestion.selectedChain)
        model.didSelectSuggestion(chain: suggestion.selectedChain)
        endEditing()
    }
}
