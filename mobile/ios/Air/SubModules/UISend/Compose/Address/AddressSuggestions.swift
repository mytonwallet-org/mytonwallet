import WalletContext
import WalletCore
import SwiftUI
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
    var addresses: [SavedAddress] { model.$account.savedAddresses.getMatching(searchString) }
    var matchingAccountIds: OrderedSet<String> {
        let searchString = self.searchString
        let otherAccountIds = accountStore.orderedAccountIds
            .filter { $0 != model.account.id }
            
        return searchString.isEmpty ? otherAccountIds : otherAccountIds
            .filter {
                let account = accountStore.get(accountId: $0)
                return account.displayName.lowercased().contains(searchString) || account.firstAddress.lowercased().contains(searchString)
            }
    }
    
    var body: some View {
        WithPerceptionTracking {
            let addresses = self.addresses
            let matchingAccountIds = self.matchingAccountIds
            
            if !addresses.isEmpty {
                InsetSection {
                    ForEach(addresses, id: \.self) { saved in
                        let account = MAccount(id: saved.address + "-mainnet", title: saved.name, type: .view, byChain: [saved.chain.rawValue: AccountChain(address: saved.address)], isTemporary: true)
                        SavedAddressButton(model: model, savedAddress: saved, accountContext: model.$account, account: AccountContext(source: .constant(account)))
                    }
                } header: {
                    Text(lang("$saved_addresses_header"))
                }
            }
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
    }
}

struct SavedAddressButton: View {

    let model: AddressInputModel
    var savedAddress: SavedAddress
    var accountContext: AccountContext
    @State var account: AccountContext

    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: onTap) {
            AccountListCell(accountContext: account, isReordering: false, showCurrentAccountHighlight: false)
        }
        .contextMenu {
            Button(role: .destructive) {
                accountContext.savedAddresses.delete(savedAddress)
            } label: {
                Label(lang("Remove"), systemImage: "trash")
            }
        }
    }
    
    func onTap() {
        model.source = .account(account.wrappedValue)
        endEditing()
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
        model.source = .account(account.wrappedValue)
        endEditing()
    }
}
