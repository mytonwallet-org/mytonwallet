//
//  IntroNavigation.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import UIKit
import SwiftUI
import WalletCore
import WalletContext
import UIComponents
import UIPasscode
import Ledger
import UISettings

enum WalletSetupResult {
    case completed
    case deferredToPasscode
}

@MainActor public final class IntroModel {
    
    public let network: ApiNetwork
    private var password: String?
    private var words: [String]?
    
    let allowOpenWithoutChecking: Bool = IS_DEBUG_OR_TESTFLIGHT
    var hasExistingPassword: Bool {
        password?.nilIfEmpty != nil
    }
    
    public init(network: ApiNetwork, password: String?, words: [String]? = nil) {
        self.network = network
        self.password = password
        self.words = words
    }
       
    // MARK: - Navigation
    
    func onAbout() {
        push(AboutVC(showLegalSection: false))
    }
    
    func onUseResponsibly() {
        push(UseResponsiblyVC())
    }
    
    func onCreateWallet() {
        push(CreateBackupDisclaimerVC(introModel: self))
    }
    
    func onImportExisting() {
        let vc = ImportExistingPickerVC(introModel: self)
        let nc = UINavigationController(rootViewController: vc)
        topWViewController()?.present(nc, animated: true)
    }
    
    func onImportMnemonic() {
        topWViewController()?.dismiss(animated: true, completion: {
            push(ImportWalletVC(introModel: self))
        })
    }
    
    func onAddViewWallet() {
        topWViewController()?.dismiss(animated: true, completion: {
            push(AddViewWalletVC(introModel: self))
        })
    }
    
    func onLedger() {
        topWViewController()?.dismiss(animated: true, completion: {
            Task { @MainActor in
                let model = await LedgerAddAccountModel()
                let vc = LedgerAddAccountVC(model: model, showBackButton: true)
                let hadExistingAccounts = !AccountStore.accountsById.isEmpty
                vc.onDone = { vc in
                    self.onDone(
                        successKind: .imported,
                        hadExistingAccounts: hadExistingAccounts,
                        importedAccountsCount: model.importedAccountsCount
                    )
                }
                push(vc)
            }
        })
    }
    
    func onGoToWords() async throws {
        let words = try await Api.generateMnemonic()
        self.words = words
        let nc = try getNavigationController()
        let wordsVC = WordDisplayVC(introModel: self, wordList: words)
        let intro = nc.viewControllers.first ?? IntroVC(introModel: self)
        push(wordsVC, completion: { _ in
            nc.viewControllers = [intro, wordsVC] // remove disclaimer
        })
    }
    
    func onLetsCheck() async throws {
        let words = try words.orThrow()
        let allWords = try await Api.getMnemonicWordList()
        push(WordCheckVC(introModel: self, words: words, allWords: allWords))
    }
    
    func onOpenWithoutChecking() async throws -> WalletSetupResult {
        try await onCheckPassed()
    }
    
    @discardableResult
    func onCheckPassed() async throws -> WalletSetupResult {
        if let password = password?.nilIfEmpty {
            try await _createWallet(passcode: password, biometricsEnabled: nil)
            return .completed
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { biometricsEnabled, password in
                try await self._createWallet(passcode: password, biometricsEnabled: biometricsEnabled)
            })
            push(setPasscode)
            return .deferredToPasscode
        }
    }
    
    public func onDone(successKind: SuccessKind, hadExistingAccounts: Bool, importedAccountsCount: Int = 1) {
        if hadExistingAccounts {
            onOpenWallet()
        } else {
            let success = ImportSuccessVC(successKind, introModel: self, importedAccountsCount: importedAccountsCount)
            push(success) { nc in
                nc.viewControllers = [success] // no going back
            }
        }
    }
    
    @discardableResult
    func onWordInputContinue(words: [String]) async throws -> WalletSetupResult {
        if let password = password?.nilIfEmpty {
            try await _importWallet(words: words, passcode: password, biometricsEnabled: nil)
            return .completed
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { biometricsEnabled, password in
                try await self._importWallet(words: words, passcode: password, biometricsEnabled: biometricsEnabled)
            })
            push(setPasscode)
            return .deferredToPasscode
        }

    }
    
    func onAddViewWalletContinue(address: String) async throws {
        try await _addViewWallet(address: address)
    }
    
    func onOpenWallet() {
        Task { @MainActor in
            if WalletContextManager.delegate?.isWalletReady == true {
                topWViewController()?.dismiss(animated: true)
                AppActions.showHome(popToRoot: true)
            } else {
                AppActions.transitionToRootState(.active, animationDuration: 0.35)
            }
        }
    }
    
    // MARK: - Actions
    
    private func _createWallet(passcode: String, biometricsEnabled: Bool?) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        let accounts = try await AccountStore.importMnemonic(network: network, words: words.orThrow(), passcode: passcode, version: nil)
        KeychainHelper.save(biometricPasscode: passcode)
        if let biometricsEnabled { // nil if not first wallet
            AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
        }
        self.onDone(successKind: .created, hadExistingAccounts: hadExistingAccounts, importedAccountsCount: accounts.count)
    }
    
    private func _importWallet(words: [String], passcode: String, biometricsEnabled: Bool?) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        let importedAccountsCount: Int
        if let privateKeyWords = normalizeMnemonicPrivateKey(words) {
            _ = try await AccountStore.importPrivateKey(network: network, privateKey: privateKeyWords[0], passcode: passcode)
            importedAccountsCount = 1
        } else {
            let accounts = try await AccountStore.importMnemonic(network: network, words: words, passcode: passcode, version: nil)
            importedAccountsCount = accounts.count
        }
        KeychainHelper.save(biometricPasscode: passcode)
        if let biometricsEnabled { // nil if not first wallet
            AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
        }
        self.onDone(successKind: .imported, hadExistingAccounts: hadExistingAccounts, importedAccountsCount: importedAccountsCount)
    }
    
    private func _addViewWallet(address: String) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        var addressByChain: [String: String] = [:]
        for chain in ApiChain.allCases {
            if chain.isValidAddressOrDomain(address) {
                addressByChain[chain.rawValue] = address
            }
        }
        _ = try await AccountStore.importViewWallet(network: network, addressByChain: addressByChain)
        self.onDone(successKind: .importedView, hadExistingAccounts: hadExistingAccounts)
    }
}

@MainActor private func getNavigationController() throws -> WNavigationController {
    try (topWViewController()?.navigationController as? WNavigationController).orThrow("can't find navigation controller")
}

@MainActor private func push(_ viewController: UIViewController, completion: ((UINavigationController) -> ())? = nil) {
    if let nc = topWViewController()?.navigationController {
        nc.pushViewController(viewController, animated: true, completion: { completion?(nc) })
    }
}
