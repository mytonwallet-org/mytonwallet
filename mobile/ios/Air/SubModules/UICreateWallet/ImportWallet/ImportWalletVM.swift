//
//  ImportWalletVM.swift
//  UICreateWallet
//
//  Created by Sina on 4/21/23.
//

import Foundation
import UIComponents
import WalletCore
import WalletContext

public protocol ImportWalletVMDelegate: AnyObject {
    var isLoading: Bool { get set }
    func goNext(didImport: Bool,  wordsToImport: [String]?)
    func errorOccured(failure: any Error)
}

public struct WalletCreatedPreloadState {
}

public class ImportWalletVM {
    
    weak var importWalletVMDelegate: ImportWalletVMDelegate?
    public init(importWalletVMDelegate: ImportWalletVMDelegate) {
        self.importWalletVMDelegate = importWalletVMDelegate
    }
    
    func validateWords(enteredWords: [String]) {
        Task { @MainActor in
            do {
                let ok = try await Api.validateMnemonic(mnemonic: enteredWords)
                if ok {
                    importWalletVMDelegate?.goNext(didImport: false, wordsToImport: enteredWords)
                } else {
                    throw BridgeCallError.message(.invalidMnemonic, nil)
                }
            } catch {
                importWalletVMDelegate?.errorOccured(failure: error)
            }
        }
    }
    
    func _importWallet(enteredWords: [String], passcode: String) {
        if importWalletVMDelegate?.isLoading ?? true {
            return
        }
        importWalletVMDelegate?.isLoading = true

        Task { @MainActor in
            do {
                _ = try await AccountStore.importMnemonic(network: .mainnet, words: enteredWords, passcode: passcode, version: nil)
                importWalletVMDelegate?.goNext(didImport: true, wordsToImport: nil)
            } catch {
                importWalletVMDelegate?.errorOccured(failure: error)
            }
            importWalletVMDelegate?.isLoading = false
        }
    }
}

