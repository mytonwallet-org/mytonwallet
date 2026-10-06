import Foundation
import Testing
@testable import WalletCore

@Suite("Passcode setup recovery", .serialized)
@MainActor
struct PasscodeSetupRecoveryTests {
    @Test
    func `allows setup without software wallets including Ledger and watch-only installs`() throws {
        let accountLists: [[String: [String: Any]]?] = [
            nil,
            [:],
            ["watch": ["type": "view"]],
            ["ledger": ["type": "ledger"]],
            ["watch": ["type": "view"], "ledger": ["type": "ledger"]],
        ]
        for accounts in accountLists {
            try AuthSupportImpl.validatePasscodeSetup(hasEncryptedAccounts: false, loadStoredAccounts: { accounts })
        }
    }

    @Test
    func `native software wallets prevent replacement even when keychain accounts are missing`() {
        #expect(throws: AuthSupportError.self) {
            try AuthSupportImpl.validatePasscodeSetup(hasEncryptedAccounts: true, loadStoredAccounts: { nil })
        }
    }

    @Test
    func `Classic accounts remain protected before SQLite migration`() {
        // Older Classic records can omit type and keep ciphertext in a separate map.
        let accounts: [String: [String: Any]] = ["0-ton-mainnet": ["address": "legacy-address"]]
        for legacyState in [StartupLegacyAccountsState.unknown, .present] {
            let evidence = StartupWalletEvidence(
                databaseAccountCount: 0,
                keychainAccountCount: accounts.count,
                legacyAccountsState: legacyState
            )
            #expect(!evidence.shouldDeletePreviousInstallAccountsOnFirstLaunch)
            #expect(!evidence.canContinueWithoutBlockingLegacyFailure)
        }
        #expect(throws: AuthSupportError.self) {
            try AuthSupportImpl.validatePasscodeSetup(hasEncryptedAccounts: false, loadStoredAccounts: { accounts })
        }
    }

    @Test
    func `persisted software wallets and unknown account formats prevent replacement`() {
        let accounts: [[String: Any]] = [
            ["type": "ton"],
            ["type": "bip39"],
            ["type": "ton", "mnemonicEncrypted": "legacy-ciphertext"],
            ["mnemonicEncrypted": "legacy-ciphertext"],
            ["type": "view", "mnemonicEncrypted": "legacy-ciphertext"],
            ["type": "ledger", "mnemonicEncrypted": "legacy-ciphertext"],
            ["type": "hardware"],
            ["type": "future-type"],
            [:],
        ]
        for account in accounts {
            #expect(throws: AuthSupportError.self) {
                try AuthSupportImpl.validatePasscodeSetup(hasEncryptedAccounts: false, loadStoredAccounts: { ["0-mainnet": account] })
            }
        }
    }

    @Test
    func `storage failures do not authorize destructive recovery`() {
        enum ReadFailure: Error { case locked, malformed }
        for error in [ReadFailure.locked, .malformed] {
            #expect(throws: ReadFailure.self) {
                try AuthSupportImpl.validatePasscodeSetup(hasEncryptedAccounts: false, loadStoredAccounts: { throw error })
            }
        }
    }

}
