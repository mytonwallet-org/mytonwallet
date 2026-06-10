import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception
import Dependencies

struct LinkDomainView: View {
    let viewModel: LinkDomainViewModel

    @Dependency(\.tokenStore) private var tokenStore
    @Dependency(\.accountStore) private var accountStore

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            let suggestedAccountIds = suggestedWalletAccountIds
            let shouldShowBottomBar = shouldShowBottomBar(suggestedAccountIds: suggestedAccountIds)
            InsetList(topPadding: 16, spacing: 24) {
                if let nft = viewModel.nft {
                    InsetSection {
                        NftPreviewRow(nft: nft, verticalPadding: 12)
                    }
                }
                InsetSection {
                    LinkDomainAddressInput(viewModel: viewModel)
                } header: {
                    Text(viewModel.addressLabel)
                }
                Group {
                    if viewModel.isAddressFocused {
                        LinkDomainWalletSuggestions(viewModel: viewModel, matchingAccountIds: suggestedAccountIds)
                            .transition(.opacity.combined(with: .offset(y: -10)))
                    }
                }
                .animation(.default, value: viewModel.isAddressFocused)
                if let error = viewModel.errorMessage {
                    WarningView(text: error, kind: .error)
                        .padding(.horizontal, 16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if shouldShowBottomBar {
                    bottomBar
                }
            }
            .animation(.default, value: shouldShowBottomBar)
            .task(id: viewModel.nft?.id) {
                await viewModel.loadDraft()
            }
        }
    }

    private var suggestedWalletAccountIds: [String] {
        guard let chain = viewModel.nft?.chain else { return [] }
        let searchString = viewModel.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = searchString.isEmpty ? nil : Regex<Substring>(verbatim: searchString).ignoresCase()
        let accountsById = accountStore.accountsById
        return accountStore.orderedAccountIds.compactMap { accountId in
            guard let account = accountsById[accountId] else { return nil }
            guard account.network == viewModel.account.network, account.supports(chain: chain) else { return nil }
            if let regex, !account.matches(regex) { return nil }
            return accountId
        }
    }

    private func shouldShowBottomBar(suggestedAccountIds: [String]) -> Bool {
        !(viewModel.isAddressFocused && !suggestedAccountIds.isEmpty && !viewModel.isAddressValid)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let fee = viewModel.fee, let chain = viewModel.nft?.chain {
                FeeView(
                    token: tokenStore.getNativeToken(chain: chain),
                    nativeToken: tokenStore.getNativeToken(chain: chain),
                    fee: fee,
                    explainedTransferFee: nil,
                    includeLabel: true
                )
                .font(.system(size: 14))
                .foregroundStyle(Color.air.secondaryLabel)
                .transition(.opacity.animation(.default))
            }
            Button(action: { viewModel.onLink?() }) {
                Text(viewModel.linkButtonTitle)
            }
            .buttonStyle(.airPrimary)
            .disabled(!viewModel.canLink)
            .environment(\.isLoading, viewModel.isButtonLoading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.air.sheetBackground)
    }
}

struct LinkDomainNavigationHeader: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(viewModel.title)
            }
        }
    }
}

private struct LinkDomainAddressInput: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            InsetCell {
                @Perception.Bindable var viewModel = viewModel
                HStack {
                    AddressTextField(
                        value: $viewModel.walletAddress,
                        isFocused: $viewModel.isAddressFocused,
                        onNext: { viewModel.isAddressFocused = false }
                    )
                    .offset(y: 1)
                    .background(alignment: .leading) {
                        if viewModel.walletAddress.isEmpty {
                            Text(lang("Wallet address or domain"))
                                .foregroundStyle(Color(UIColor.placeholderText))
                        }
                    }
                    .opacity(!viewModel.walletAddress.isEmpty && !viewModel.isAddressFocused ? 0 : 1)
                    .overlay(alignment: .leading) {
                        if !viewModel.walletAddress.isEmpty && !viewModel.isAddressFocused {
                            LinkDomainResolvedAddressView(viewModel: viewModel)
                        }
                    }
                    
                    if viewModel.walletAddress.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: onPaste) {
                                Text(lang("Paste"))
                            }
                            Button(action: onScan) {
                                Image.airBundle("ScanIcon")
                            }
                        }
                        .offset(x: 4)
                        .padding(.vertical, -1)
                    } else {
                        Button(action: onClear) {
                            Image(systemName: "xmark.circle.fill")
                                .tint(.air.secondaryLabel)
                                .imageScale(.small)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func onPaste() {
        if let pastedAddress = UIPasteboard.general.string, !pastedAddress.isEmpty {
            viewModel.walletAddress = pastedAddress
            endEditing()
        } else {
            AppActions.showToast(message: lang("Clipboard empty"))
        }
    }

    private func onScan() {
        Task {
            endEditing()
            if let result = await AppActions.scanQR() {
                endEditing()
                viewModel.applyScanResult(result)
            }
        }
    }

    private func onClear() {
        viewModel.walletAddress = ""
        viewModel.selectedWalletAccount = nil
        viewModel.walletAddressName = nil
        viewModel.resolvedWalletAddress = nil
    }
}

private struct LinkDomainWalletSuggestions: View {
    var viewModel: LinkDomainViewModel
    let matchingAccountIds: [String]

    var body: some View {
        WithPerceptionTracking {
            if !matchingAccountIds.isEmpty {
                InsetSection {
                    ForEach(matchingAccountIds, id: \.self) { accountId in
                        LinkDomainWalletButton(
                            viewModel: viewModel,
                            account: AccountContext(accountId: accountId)
                        )
                    }
                } header: {
                    Text(lang("My"))
                }
            }
        }
    }
}

private struct LinkDomainWalletButton: View {
    var viewModel: LinkDomainViewModel
    @State var account: AccountContext

    var body: some View {
        InsetButtonCell(horizontalPadding: 12, verticalPadding: 10, action: onTap) {
            AccountListCell(accountContext: account, isReordering: false, showCurrentAccountHighlight: false)
        }
    }

    private func onTap() {
        viewModel.selectWalletAccount(account.wrappedValue)
        viewModel.isAddressFocused = false
        endEditing()
    }
}

private struct LinkDomainResolvedAddressView: View {
    var viewModel: LinkDomainViewModel

    var body: some View {
        WithPerceptionTracking {
            let display = viewModel.displayComponents()
            HStack(spacing: 4) {
                if let primary = display.primary {
                    Text(primary)
                        .foregroundStyle(Color.air.primaryLabel)
                        .truncationMode(.middle)
                }
                if let secondary = display.secondary {
                    Text("·")
                        .foregroundStyle(Color.air.secondaryLabel)
                    Text(secondary)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
            }
            .animation(.default, value: display.primary)
            .animation(.default, value: display.secondary)
        }
    }
}
