import SwiftUI
import UIAssets
import UIComponents
import WalletContext
import WalletCore

struct WalletCardSettingsSection: View {
    @AppStorage(WalletCardSettings.topLineUserDefaultsKey)
    private var cardTopLineRawValue = WalletCardTopLine.defaultValue.rawValue

    @AppStorage(WalletActionButtonsSettings.hideActionButtonsRowUserDefaultsKey)
    private var hidesActionButtonsRow = false

    var body: some View {
        InsetSection {
            InsetPickerCell(
                lang("Show on Card"),
                selection: $cardTopLineRawValue,
                value: (WalletCardTopLine(rawValue: cardTopLineRawValue) ?? .defaultValue).title
            ) {
                ForEach(WalletCardTopLine.allCases, id: \.rawValue) { topLine in
                    Text(topLine.title).tag(topLine.rawValue)
                }
            }

            InsetDetailCell(horizontalPadding: 16, verticalPadding: 0) {
                Text(lang("Action Buttons"))
                    .frame(minHeight: 44)
            } value: {
                Toggle(lang("Action Buttons"), isOn: showsActionButtonsRow)
                    .labelsHidden()
            }
        } footer: {
            Text(lang("$settings_wallet_card_description"))
        }
        .onChange(of: hidesActionButtonsRow) { _ in
            WalletActionButtonsSettings.notifyDidChange()
        }
    }

    private var showsActionButtonsRow: Binding<Bool> {
        Binding(
            get: { !hidesActionButtonsRow },
            set: { hidesActionButtonsRow = !$0 }
        )
    }
}

struct WalletDisplaySettingsSection: View {
    @State private var walletTokensLimit = AppStorageHelper.homeWalletVisibleTokensLimit.rawValue
    @State private var homeActivityLimit = AppStorageHelper.homeActivityVisibleItemsLimit.rawValue
    @State private var showsCollectiblesSection: Bool
    @State private var walletAssetsViewModel: WalletAssetsViewModel

    init() {
        let walletAssetsViewModel = WalletAssetsViewModel(accountSource: .current)
        self._walletAssetsViewModel = State(initialValue: walletAssetsViewModel)
        self._showsCollectiblesSection = State(initialValue: !walletAssetsViewModel.isCollectiblesHidden)
    }

    var body: some View {
        InsetSection {
            InsetPickerCell(
                lang("Tokens"),
                selection: $walletTokensLimit,
                value: HomeWalletVisibleTokensLimit(storedValue: walletTokensLimit).title
            ) {
                ForEach(HomeWalletVisibleTokensLimit.allCases, id: \.rawValue) { limit in
                    Text(limit.title).tag(limit.rawValue)
                }
            }

            InsetDetailCell(horizontalPadding: 16, verticalPadding: 0) {
                Text(lang("Collectibles Section"))
                    .frame(minHeight: 44)
            } value: {
                Toggle(lang("Collectibles Section"), isOn: $showsCollectiblesSection)
                    .labelsHidden()
            }

            InsetPickerCell(
                lang("Activity"),
                selection: $homeActivityLimit,
                value: HomeActivityVisibleItemsLimit(storedValue: homeActivityLimit).title
            ) {
                ForEach(HomeActivityVisibleItemsLimit.allCases, id: \.rawValue) { limit in
                    Text(limit.title).tag(limit.rawValue)
                }
            }
        } header: {
            Text(lang("Wallet"))
        }
        .onChange(of: walletTokensLimit) { limit in
            AppStorageHelper.homeWalletVisibleTokensLimit = .init(storedValue: limit)
        }
        .onChange(of: homeActivityLimit) { limit in
            AppStorageHelper.homeActivityVisibleItemsLimit = .init(storedValue: limit)
        }
        .onChange(of: showsCollectiblesSection) { isShown in
            Task {
                try? await walletAssetsViewModel.setCollectiblesHidden(!isShown)
            }
        }
    }
}
