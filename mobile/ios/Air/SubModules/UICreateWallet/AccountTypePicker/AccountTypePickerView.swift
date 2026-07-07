import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import UIPasscode
import Perception

struct AccountTypePickerView: View {

    var network: ApiNetwork
    var onHeightChange: (CGFloat) -> ()
    var onViewAddress: () -> ()
    var onLedger: () -> ()

    @Environment(\.dismiss) var dismiss

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 0) {
                    InsetSection(addDividers: false) {
                        WalletPickerOptionRow(
                            icon: "CreateWalletIcon30",
                            title: lang("New Wallet"),
                            subtitle: lang("From new secret words"),
                            showsDivider: canCreateSubwallet,
                            onTap: onCreate
                        )

                        if canCreateSubwallet {
                            WalletPickerOptionRow(
                                icon: "NewSubwalletIcon30",
                                title: lang("New Subwallet"),
                                subtitle: lang("From current secret words"),
                                onTap: onCreateSubwallet
                            )
                        }
                    }

                    WalletPickerSectionTitle()

                    InsetSection(addDividers: false) {
                        WalletPickerOptionRow(
                            icon: "KeyIcon30",
                            title: lang("$secret_words"),
                            subtitle: lang("Restore wallet from 12 or 24 words"),
                            showsDivider: network == .mainnet,
                            onTap: onImport
                        )
                        if network == .mainnet {
                            WalletPickerOptionRow(
                                icon: "LedgerIcon30",
                                title: lang("Ledger"),
                                subtitle: lang("Connect your hardware wallet"),
                                onTap: onLedger
                            )
                        }
                    }

                    InsetSection(addDividers: false) {
                        WalletPickerOptionRow(
                            icon: "ViewIcon30",
                            title: lang("View Any Address"),
                            subtitle: lang("Watch wallet in read-only mode"),
                            onTap: onViewAddress
                        )
                    }
                    .padding(.top, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    onHeightChange(height)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .backportScrollBounceBehaviorBasedOnSize()
        }
    }

    private var canCreateSubwallet: Bool {
        guard let account = AccountStore.account, account.type == .mnemonic, account.network == network else {
            return false
        }

        return account.orderedChains.contains { chain, _ in
            account.supportsSubwallets(on: chain)
        }
    }

    private func onCreate() {
        dismiss()
        if let vc = topViewController() {
            UnlockVC.presentAuth(on: vc, onDone: { passcode in
                Task { @MainActor in
                    do {
                        let words = try await Api.generateMnemonic()
                        let introModel = IntroModel(network: network, password: passcode, words: words)
                        let addAccountVC = WordDisplayVC(introModel: introModel, wordList: words)
                        let navVC = WNavigationController(rootViewController: addAccountVC)
                        topViewController()?.present(navVC, animated: true)
                    } catch {
                        AppActions.showError(error: error)
                    }
                }
            }, cancellable: true)
        }
    }

    private func onCreateSubwallet() {
        dismiss()
        if let vc = topViewController() {
            UnlockVC.presentAuth(on: vc, onDone: { passcode in
                Task { @MainActor in
                    guard let passcode else { return }
                    do {
                        let account = try await AccountStore.createSubWallet(password: passcode)
                        AppActions.showHome(popToRoot: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            AppActions.showToast(
                                style: .large,
                                icon: .symbolImage("plus"),
                                message: lang("Subwallet Created"),
                                actionTitle: lang("Set Name")
                            ) {
                                AppActions.showRenameAccount(accountId: account.id)
                            }
                        }
                    } catch {
                        AppActions.showError(error: error)
                    }
                }
            }, cancellable: true)
        }
    }

    private func onImport() {
        dismiss()
        if let vc = topViewController() {
            UnlockVC.presentAuth(on: vc, onDone: { passcode in
                Task { @MainActor in
                    let introModel = IntroModel(network: network, password: passcode)
                    let importWalletVC = ImportWalletVC(introModel: introModel)
                    let navVC = WNavigationController(rootViewController: importWalletVC)
                    topViewController()?.present(navVC, animated: true)
                }
            }, cancellable: true)
        }
    }
}
