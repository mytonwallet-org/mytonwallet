//
//  SplashVM.swift
//  MyTonWallet
//
//  Created by Sina on 3/16/24.
//

import Foundation
import WalletContext
import WalletCore

private let log = Log("SplashVM")

protocol SplashVMDelegate: AnyObject {
    // called when user does not have a wallet yet
    func navigateToIntro()
    
    // called when the wallet data is complete and user should see wallet home screen (wallet info)
    func navigateToHome()

}

final class SplashVM: NSObject {
    
    private weak var splashVMDelegate: SplashVMDelegate?
    init(splashVMDelegate: SplashVMDelegate) {
        self.splashVMDelegate = splashVMDelegate
        super.init()
    }
    
    private(set) var appStarted = false

    // should make sure that bridge is ready, before launching startApp method logic!
    var bridgeIsReady = false {
        didSet {
            if bridgeIsReady {
                if waitingForBridge {
                    waitingForBridge = false
                    startApp()
                }
            }
        }
    }
    private var waitingForBridge = false
    
    // get wallet data and present correct page on the navigation controller
    func startApp() {
        log.info("startApp")
        appStarted = false

        if !bridgeIsReady {
            waitingForBridge = true
            return
        }

        // check if any accounts has been added
        guard let activeAccountId = AccountStore.accountId else {
            appStarted = true
            splashVMDelegate?.navigateToIntro()
            return
        }
        // try to validate account
        log.info("activating account \(activeAccountId, .public)")
        Task { @MainActor in
            do {
                let account = try await AccountStore.activateAccount(accountId: activeAccountId)
                self.fetched(account: account)
            } catch {
                log.fault("failed to activate account: \(error, .public) id=\(activeAccountId, .public)")
                // try to activate any other account
                for accountId in AccountStore.orderedAccountIds {
                    do {
                        let account = try await AccountStore.activateAccount(accountId: accountId)
                        self.fetched(account: account)
                        return
                    } catch {
                        log.fault("failed to activate fallback account: \(error, .public) id=\(activeAccountId, .public)")
                        continue
                    }
                }
                LogStore.shared.syncronize()
                try! await AccountStore.resetAccounts()
            }
            do {
                try await AccountStore.removeAllTemporaryAccounts()
            } catch {
                log.error("failed to remove all temporary accounts: \(error, .public)")
            }
        }
    }
    
    private func fetched(account: Any?) {
        guard account != nil else {
            // SHOULD NOT HAPPEN!
            return
        }
        appStarted = true
        // Account validated
        splashVMDelegate?.navigateToHome()
    }
}
