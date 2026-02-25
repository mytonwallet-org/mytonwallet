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

private let log = Log("IntroActions")

@MainActor public final class IntroModel {
    
    public let network: ApiNetwork
    private var password: String?
    private var words: [String]?
    
    let allowOpenWithoutChecking: Bool = IS_DEBUG_OR_TESTFLIGHT
    
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
                vc.onDone = { vc in
                    self.onDone(successKind: .imported)
                }
                push(vc)
            }
        })
    }
    
    func onGoToWords() {
        Task { @MainActor in
            do {
                let words = try await Api.generateMnemonic()
                self.words = words
                let nc = try getNavigationController()
                let wordsVC = WordDisplayVC(introModel: self, wordList: words)
                let intro = nc.viewControllers.first ?? IntroVC(introModel: self)
                push(wordsVC, completion: { _ in
                    nc.viewControllers = [intro, wordsVC] // remove disclaimer
                })
            } catch {
                log.error("onGoToWords: \(error)")
                assertionFailure("\(error)")
            }
        }
    }
    
    func onLetsCheck() {
        Task { @MainActor in
            do {
                let words = try words.orThrow()
                let allWords = try await Api.getMnemonicWordList()
                push(WordCheckVC(introModel: self, words: words, allWords: allWords))
            } catch {
                log.error("onLetsCheck: \(error, .public)")
            }
        }
    }
    
    func onOpenWithoutChecking() {
        onCheckPassed()
    }
    
    func onCheckPassed() {
        if let password = password?.nilIfEmpty {
            _createWallet(passcode: password, biometricsEnabled: nil)
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { biometricsEnabled, password in
                self._createWallet(passcode: password, biometricsEnabled: biometricsEnabled)
            })
            push(setPasscode)
        }
    }
    
    public func onDone(successKind: SuccessKind) {
        if AccountStore.accountsById.count >= 2 {
            onOpenWallet()
        } else {
            let success = ImportSuccessVC(successKind, introModel: self)
            push(success) { nc in
                nc.viewControllers = [success] // no going back
            }
        }
    }
    
    func onWordInputContinue(words: [String]) {
        if let password = password?.nilIfEmpty {
            _importWallet(words: words, passcode: password, biometricsEnabled: nil)
        } else {
            let setPasscode = SetPasscodeVC(onCompletion: { biometricsEnabled, password in
                self._importWallet(words: words, passcode: password, biometricsEnabled: biometricsEnabled)
            })
            push(setPasscode)
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
    
    private func _createWallet(passcode: String, biometricsEnabled: Bool?) {
        Task { @MainActor in
            do {
                _ = try await AccountStore.importMnemonic(network: network, words: words.orThrow(), passcode: passcode, version: nil)
                KeychainHelper.save(biometricPasscode: passcode)
                if let biometricsEnabled { // nil if not first wallet
                    AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
                }
                self.onDone(successKind: .created)
            } catch {
                log.error("_createWallet: \(error)")
            }
        }
    }
    
    private func _importWallet(words: [String], passcode: String, biometricsEnabled: Bool?) {
        Task { @MainActor in
            do {
                if let privateKeyWords = normalizeMnemonicPrivateKey(words) {
                    _ = try await AccountStore.importPrivateKey(network: network, privateKey: privateKeyWords[0], passcode: passcode)
                } else {
                    _ = try await AccountStore.importMnemonic(network: network, words: words, passcode: passcode, version: nil)
                }
                KeychainHelper.save(biometricPasscode: passcode)
                if let biometricsEnabled { // nil if not first wallet
                    AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
                }
                self.onDone(successKind: .imported)
            } catch {
                log.error("_importWallet: \(error)")
            }
        }
    }
    
    private func _addViewWallet(address: String) async throws {
        var addressByChain: [String: String] = [:]
        for chain in ApiChain.allCases {
            if chain.isValidAddressOrDomain(address) {
                addressByChain[chain.rawValue] = address
            }
        }
        _ = try await AccountStore.importViewWallet(network: network, addressByChain: addressByChain)
        self.onDone(successKind: .importedView)
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
