import Dependencies
import Perception
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct CrosschainFromWalletView: View {
    let model: CrosschainFromWalletModel
    let onClose: () -> Void
    let onContinue: () -> Void

    var body: some View {
        WithPerceptionTracking {
            InsetList(topPadding: 28, spacing: 24) {
                SwapOverviewView(
                    fromAmount: model.sellingToken,
                    toAmount: model.buyingToken
                )
                .padding(.horizontal, 16)

                InsetSection {
                    AddressInputCell(model: model)
                } footer: {
                    Text(model.infoText)
                        .foregroundStyle(model.hasAddressError ? Color.air.error : Color.air.secondaryLabel)
                }

                if model.isAddressFocused && model.showsSuggestions {
                    CrosschainSuggestions(model: model)
                        .transition(.opacity.combined(with: .offset(y: -10)))
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                BottomButtons(
                    canContinue: model.canContinue,
                    onClose: onClose,
                    onContinue: onContinue
                )
            }
            .animation(.default, value: model.isAddressFocused)
            .contentShape(.rect)
            .onTapGesture {
                endEditing()
            }
        }
    }
}

private struct AddressInputCell: View {
    let model: CrosschainFromWalletModel

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetCell {
                HStack(alignment: .top, spacing: 12) {
                    AddressTextField(
                        value: $model.addressWithTrimming,
                        isFocused: $model.isAddressFocused,
                        maximumNumberOfLines: 0,
                        onNext: { model.isAddressFocused = false }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .offset(y: 1)
                    .background(alignment: .topLeading) {
                        if model.addressInputString.isEmpty {
                            Text(lang("Your address on another blockchain"))
                                .foregroundStyle(Color(UIColor.placeholderText))
                                .lineLimit(1)
                                .padding(.top, 1)
                        }
                    }

                    if model.toAddress.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: onScan) {
                                Image.airBundle("ScanIcon")
                            }
                            Button(action: model.pasteAddress) {
                                Text(lang("Paste"))
                            }
                        }
                        .fixedSize()
                        .buttonStyle(.borderless)
                        .padding(.top, 1)
                    } else {
                        Button(action: model.clearAddress) {
                            Image(systemName: "xmark.circle.fill")
                                .tint(.air.secondaryLabel)
                                .imageScale(.small)
                        }
                        .fixedSize()
                        .buttonStyle(.borderless)
                        .padding(.top, 1)
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                model.isAddressFocused = true
            }
        }
    }

    private func onScan() {
        Task {
            endEditing()
            if let result = await AppActions.scanQR() {
                endEditing()
                model.handleScanResult(result)
            }
        }
    }
}

private struct CrosschainSuggestions: View {
    let model: CrosschainFromWalletModel

    @Dependency(\.accountStore) private var accountStore

    private var searchString: String {
        model.addressInputString.lowercased()
    }

    private var targetChain: ApiChain {
        model.buyingToken.type.chain
    }

    private var matchingSavedAddresses: [SavedAddress] {
        guard model.showsSuggestions else { return [] }
        return model.$account.savedAddresses.getMatching(searchString)
            .filter { $0.chain == targetChain }
    }

    private var matchingAccountIds: [String] {
        guard model.showsSuggestions else { return [] }
        let isEmpty = searchString.isEmpty
        let regex = Regex<Substring>(verbatim: searchString).ignoresCase()
        let network = model.account.network
        let currentAccountId = model.account.id
        let accountsById = accountStore.accountsById

        return accountStore.orderedAccountIds.filter { accountId in
            guard let account = accountsById[accountId] else { return false }
            guard account.network == network else { return false }
            guard account.supports(chain: targetChain) else { return false }
            return accountId == currentAccountId || isEmpty || account.matches(regex)
        }
    }

    var body: some View {
        WithPerceptionTracking {
            if !matchingSavedAddresses.isEmpty {
                InsetSection {
                    ForEach(matchingSavedAddresses, id: \.self) { savedAddress in
                        SavedAddressButton(savedAddress: savedAddress, targetChain: targetChain, onTap: onSavedAddressTap)
                    }
                } header: {
                    Text(lang("$saved_addresses_header"))
                }
            }

            if !matchingAccountIds.isEmpty {
                InsetSection {
                    ForEach(matchingAccountIds, id: \.self) { accountId in
                        AccountButton(accountId: accountId, onTap: onAccountTap)
                    }
                } header: {
                    Text(lang("My"))
                }
            }
        }
    }

    private func onSavedAddressTap(_ savedAddress: SavedAddress) {
        model.applyAddress(savedAddress.address)
        endEditing()
    }

    private func onAccountTap(_ account: MAccount) {
        guard let address = account.getAddress(chain: targetChain) else { return }
        model.applyAddress(address)
        endEditing()
    }
}

private struct SavedAddressButton: View {
    let savedAddress: SavedAddress
    let targetChain: ApiChain
    let onTap: (SavedAddress) -> Void

    private var accountContext: AccountContext {
        let byChain: [ApiChain: AccountChain] = [targetChain: AccountChain(address: savedAddress.address)]
        let account = MAccount(
            id: savedAddress.address + "-mainnet",
            title: savedAddress.name,
            type: .view,
            byChain: byChain,
            isTemporary: true
        )
        return AccountContext(source: .constant(account))
    }

    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: { onTap(savedAddress) }) {
            AccountListCell(accountContext: accountContext, isReordering: false, showCurrentAccountHighlight: false)
        }
    }
}

private struct AccountButton: View {
    let accountId: String
    let onTap: (MAccount) -> Void

    @State private var account = AccountContext(accountId: "")

    init(accountId: String, onTap: @escaping (MAccount) -> Void) {
        self.accountId = accountId
        self.onTap = onTap
        self._account = State(initialValue: AccountContext(accountId: accountId))
    }

    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: { onTap(account.wrappedValue) }) {
            AccountListCell(accountContext: account, isReordering: false, showCurrentAccountHighlight: false)
        }
    }
}

private struct BottomButtons: View {
    let canContinue: Bool
    let onClose: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Text(lang("Close"))
            }
            .buttonStyle(.airSecondary)

            Button(action: onContinue) {
                Text(lang("Continue"))
            }
            .buttonStyle(.airPrimary)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.air.sheetBackground)
    }
}
