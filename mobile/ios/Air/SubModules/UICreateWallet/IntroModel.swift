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

private let log = Log("IntroActions")

public enum IntroAuthMode: Sendable {
    case requiresPasscodeSetup
    case authorized(enclaveToken: EnclaveToken)

    public init(enclaveToken: EnclaveToken?) {
        self = if let enclaveToken {
            .authorized(enclaveToken: enclaveToken)
        } else {
            .requiresPasscodeSetup
        }
    }
}

@MainActor public final class IntroModel {
    private static let postImportToastDelay: TimeInterval = 2.0
    
    public let network: ApiNetwork
    private let authMode: IntroAuthMode
    private var words: [String]?
    private var pendingToastWorkItem: DispatchWorkItem?
    
    let allowOpenWithoutChecking: Bool = IS_DEBUG_OR_TESTFLIGHT
    var hasExistingPassword: Bool {
        cachedEnclaveToken != nil
    }
    
    public init(network: ApiNetwork, authMode: IntroAuthMode, words: [String]? = nil) {
        self.network = network
        self.authMode = authMode
        self.words = words
    }

    private var cachedEnclaveToken: EnclaveToken? {
        if case let .authorized(enclaveToken) = authMode {
            return enclaveToken
        }
        return nil
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
                let model = LedgerAddAccountModel()
                let vc = LedgerAddAccountVC(model: model)
                let hadExistingAccounts = !AccountStore.accountsById.isEmpty
                vc.onDone = { vc in
                    self.onDone(
                        successKind: .imported,
                        hadExistingAccounts: hadExistingAccounts,
                        accountIds: model.importedAccountIds
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
        if let enclaveToken = cachedEnclaveToken {
            try await _createWallet(enclaveToken: enclaveToken)
            return .completed
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { enclaveToken in
                try await self._createWallet(enclaveToken: enclaveToken)
            })
            push(setPasscode)
            return .deferredToPasscode
        }
    }
    
    public func onDone(successKind: SuccessKind, hadExistingAccounts: Bool, accountIds: [String]) {
        if hadExistingAccounts {
            onOpenWallet()

            if let singleAccountId = accountIds.count == 1 ? accountIds.first : nil {
                pendingToastWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    let message: String
                    switch successKind {
                    case .created: message = lang("Wallet Created")
                    case .imported: message = lang("Wallet Imported")
                    case .importedView: message = lang("View Wallet Added")
                    }
                    AppActions.showToast(style: .large, icon: .symbolImage("plus"), message: message, actionTitle: lang("Set Name")) {
                        AppActions.showRenameAccount(accountId: singleAccountId)
                    }
                }
                pendingToastWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.postImportToastDelay, execute: workItem)
            }
        } else {
            let success = ImportSuccessVC(successKind, introModel: self, importedAccountsCount: accountIds.count)
            push(success) { nc in
                nc.viewControllers = [success] // no going back
            }
        }
    }

    @discardableResult
    func onWordInputContinue(words: [String]) async throws -> WalletSetupResult {
        if let enclaveToken = cachedEnclaveToken {
            try await _importWallet(words: words, enclaveToken: enclaveToken)
            return .completed
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { enclaveToken in
                try await self._importWallet(words: words, enclaveToken: enclaveToken)
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
                // Allow the underlying UI to switch to the wallet screen silently
                try? await Task.sleep(for: .seconds(0.35))
                
                AppActions.showHome(popToRoot: true)
            } else {
                AppActions.transitionToRootState(.active, animationDuration: 0.35)
            }
        }
    }
    
    // MARK: - Actions

    
    private func _createWallet(enclaveToken: EnclaveToken) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        let accounts = try await AccountStore.importMnemonic(network: network, words: words.orThrow(), enclaveToken: enclaveToken)
        self.onDone(successKind: .created, hadExistingAccounts: hadExistingAccounts, accountIds: accounts.map { $0.id })
    }
    
    private func _importWallet(words: [String], enclaveToken: EnclaveToken) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        var importedAccountIds: [String] = []
        if let privateKeyWords = normalizeMnemonicPrivateKey(words) {
            let account = try await AccountStore.importPrivateKey(network: network, privateKey: privateKeyWords[0], enclaveToken: enclaveToken)
            importedAccountIds.append(account.id)
        } else {
            let accounts = try await AccountStore.importMnemonic(network: network, words: words, enclaveToken: enclaveToken)
            importedAccountIds += accounts.map { $0.id }
        }
        self.onDone(successKind: .imported, hadExistingAccounts: hadExistingAccounts, accountIds: importedAccountIds)
    }
    
    private func _addViewWallet(address: String) async throws {
        let hadExistingAccounts = !AccountStore.accountsById.isEmpty
        var addressByChain: [String: String] = [:]
        for chain in ApiChain.allCases {
            if chain.isValidAddressOrDomain(address) {
                addressByChain[chain.rawValue] = address
            }
        }
        let account = try await AccountStore.importViewWallet(network: network, addressByChain: addressByChain)
        self.onDone(successKind: .importedView, hadExistingAccounts: hadExistingAccounts, accountIds: [account.id])
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
