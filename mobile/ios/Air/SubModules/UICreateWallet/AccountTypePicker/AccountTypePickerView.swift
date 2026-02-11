//
//  AccountTypePickerView.swift
//  AirAsFramework
//
//  Created by nikstar on 25.08.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import UIPasscode
import Ledger

struct AccountTypePickerView: View {
    
    var network: ApiNetwork
    var showCreateWallet: Bool
    var showSwitchToOtherVersionIfAvailable: Bool
    var onHeightChange: (CGFloat) -> ()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            if network == .testnet {
                Text("Testnet")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .offset(y: -4)
            }
            
            if showCreateWallet {
                InsetSection(dividersInset: 50) {
                    Item(icon: "CreateWalletIcon30", text: lang("Create New Wallet"), additionalPadding: true, onTap: onCreate)
                }
                HStack(spacing: 12) {
                    Divider()
                    Text(lang("or import from"))
                    Divider()
                }
                .frame(height: 22)
                .foregroundStyle(Color(WTheme.secondaryLabel))

            }

            InsetSection(dividersInset: 50) {
                Item(icon: "KeyIcon30", text: lang("%counts% Secret Words", arg1: "12/24"), onTap: onImport)
                if network == .mainnet {
                    Item(icon: "LedgerIcon30", text: "Ledger", onTap: onLedger)
                }
            }

            InsetSection(dividersInset: 50) {
                Item(icon: "ViewIcon30", text: lang("View Any Address"), additionalPadding: true, onTap: onView)
            }
            
            if showSwitchToOtherVersionIfAvailable, let count = AccountStore.walletVersionsData?.versions.count, count > 0 {
                Text(langMd(
                    "$wallet_switch_version_1", arg1: "[\(lang("$wallet_switch_version_2"))](mock)"
                ))
                    .font(.system(size: 14))
                    .padding(.horizontal, 32)
                    .padding(.bottom, -16)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .environment(\.openURL, OpenURLAction { _ in
                        onWalletVersion()
                        return .handled
                    })
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                    .onTapGesture {
                        onWalletVersion()
                    }
                    .padding(.vertical, -10)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 32)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            onHeightChange(height)
        }
    }
    
    func onCreate() {
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
    func onImport() {
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
    func onLedger() {
        dismiss()
        if let vc = topViewController() {
            UnlockVC.presentAuth(on: vc, onDone: { passcode in
                Task { @MainActor in
                    let introModel = IntroModel(network: network, password: passcode)
                    let model = await LedgerAddAccountModel()
                    let importWalletVC = LedgerAddAccountVC(model: model, showBackButton: false)
                    importWalletVC.onDone = { _ in
                        introModel.onDone(successKind: .imported)
                    }
                    let navVC = WNavigationController(rootViewController: importWalletVC)
                    topViewController()?.present(navVC, animated: true)
                }
            }, cancellable: true)
        }
    }
    func onView() {
        dismiss()
        let vc = AddViewWalletVC(introModel: IntroModel(network: network, password: nil))
        let navVC = WNavigationController(rootViewController: vc)
        topViewController()?.present(navVC, animated: true)
    }
    
    func onWalletVersion() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppActions.showImportWalletVersion()
        }
    }
}


private struct Item: View {
    
    var icon: String
    var text: String
    var additionalPadding: Bool = false
    var onTap: () -> ()
    
    var body: some View {
        InsetButtonCell(verticalPadding: additionalPadding ? 9 : 7, action: onTap) {
            HStack(spacing: 16) {
                Image.airBundle(icon)
                    .clipShape(.rect(cornerRadius: 8))
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image.airBundle("RightArrowIcon")
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .backportGeometryGroup()
        }
    }
}

private struct Divider: View {
    var body: some View {
        Capsule()
            .frame(width: 64, height: 0.667)
            .offset(y: 1.333)
    }
}
