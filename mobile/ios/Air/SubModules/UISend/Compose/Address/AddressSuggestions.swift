import WalletContext
import WalletCore
import SwiftUI
import ContextMenuKit
import Dependencies
import UIComponents
import Perception
import OrderedCollections

struct AddressSuggestions: View {
    
    let model: AddressInputModel
    
    @Dependency(\.accountStore) var accountStore
    
    var searchString: String {
        model.textFieldInput.lowercased()
    }
    var addresses: [SavedAddress] {
        let addresses = model.$account.savedAddresses.getMatching(searchString)
        guard let targetChain = model.suggestionFilterChain else { return addresses }
        return addresses.filter { $0.chain == targetChain }
    }
    var matchingAccountIds: OrderedSet<String> {
        let isEmpty = searchString.isEmpty
        let regex = Regex<Substring>(verbatim: searchString).ignoresCase()
        let network = model.account.network
        let targetChain = model.suggestionFilterChain
        let otherAccountIds = accountStore.orderedAccountIds
            .filter { $0 != model.account.id }
        let accountsById = accountStore.accountsById
        return otherAccountIds
            .filter {
                guard let account = accountsById[$0] else { return false }
                guard account.network == network else { return false }
                if let targetChain, !account.supports(chain: targetChain) { return false }
                return isEmpty || account.matches(regex)
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
                ForEach(addresses, id: \.self) { saved in
                    let account = makeTemporaryAccount(saved: saved)
                    SavedAddressButton(model: model, savedAddress: saved, accountContext: model.$account, account: AccountContext(source: .constant(account)))
                }
            } header: {
                Text(lang("$saved_addresses_header"))
            }
        }
    }

    @ViewBuilder
    private var myAccountsSection: some View {
        if !matchingAccountIds.isEmpty {
            InsetSection {
                ForEach(matchingAccountIds, id: \.self) { accountId in
                    AccountButton(model: model, account: AccountContext(accountId: accountId))
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

struct SavedAddressButton: View {

    let model: AddressInputModel
    var savedAddress: SavedAddress
    var accountContext: AccountContext
    @State var account: AccountContext

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
            AccountListCell(accountContext: account, isReordering: false, showCurrentAccountHighlight: false)
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
        model.source = .savedAccount(account.wrappedValue, saveKey: savedAddress.address)
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

struct AccountButton: View {
    
    let model: AddressInputModel
    @State var account: AccountContext
    
    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: onTap) {
            AccountListCell(accountContext: account, isReordering: false, showCurrentAccountHighlight: false)
        }
    }
    
    func onTap() {
        model.source = .myAccount(account.wrappedValue)
        endEditing()
    }
}
