//
//  AirLauncher.swift
//  AirAsFramework
//
//  Created by Sina on 9/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import GRDB
import Dependencies


private let log = Log("AirLauncher")


@MainActor
public class AirLauncher {
    
    private static var canSwitchToCapacitor: Bool {
        // shouldn't be force unwrapped because app delegate is different in previews or widgets
        (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.canSwitchToCapacitor ?? true
    }
    
    public static var isOnTheAir: Bool {
        get {
            if canSwitchToCapacitor {
                UserDefaults.standard.object(forKey: "isOnAir") as? Bool ?? DEFAULT_TO_AIR
            } else {
                true
            }
        }
        set {
            if canSwitchToCapacitor {
                UserDefaults.standard.set(newValue, forKey: "isOnAir")
            }
        }
    }
    
    private static var window: WWindow!
    private static var startVC: SplashVC?
    
    private static var db: (any DatabaseWriter)?
    
    static var deeplinkHandler: DeeplinkHandler? = nil {
        didSet {
            if let pendingDeeplinkURL {
                _ = deeplinkHandler?.handle(pendingDeeplinkURL)
                self.pendingDeeplinkURL = nil
            }
            if let pendingNotification {
                deeplinkHandler?.handleNotification(pendingNotification)
                self.pendingNotification = nil
            }
        }
    }
    static var pendingDeeplinkURL: URL? = nil
    static var pendingNotification: UNNotification? = nil
    static var appUnlocked = false
    
    public static func set(window: WWindow) {
        AirLauncher.window = window
    }
    
    public static func soarIntoAir() async {
        log.info("soarIntoAir")
        
        do {
            do {
                try await GlobalStorage.loadFromWebView()
            } catch {
                log.fault("failed to load global storage: \(error, .public).")
                GlobalStorage.update { $0[""] = [:] }
            }
            try await GlobalStorage.migrate()
        } catch {
            log.fault("failed to initialize global storage: \(error, .public) will continue with empty storage")
            GlobalStorage.update { $0["stateVersion"] = STATE_VERSION }
            try! await GlobalStorage.syncronize()
        }
        
        log.info("connecting to database")
        
        let db = try! connectToDatabase()
        self.db = db
        WalletCore.db = db
        
        try! await switchStorageFromCapacitorIfNeeded(global: GlobalStorage, db: db)
        
        configureAppActions()
        // Prepare storage
        AppStorageHelper.reset()
        await WalletCoreData.start(db: db)

        // Load theme
        let accountId = AccountStore.accountId ?? ""
        @Dependency(\.accountSettings) var _accountSettings
        let accountSettings = _accountSettings.for(accountId: accountId)
        let activeColorTheme = accountSettings.accentColorIndex
        changeThemeColors(to: activeColorTheme)
        
        // Set animations enabled or not
        UIView.setAnimationsEnabled(AppStorageHelper.animations)
        
        let nightMode = AppStorageHelper.activeNightMode
        window?.overrideUserInterfaceStyle = nightMode.userInterfaceStyle
        window?.updateTheme()
        
        startVC = SplashVC(nibName: nil, bundle: nil)
        deeplinkHandler = DeeplinkHandler(deeplinkNavigator: startVC!)
        self.window?.rootViewController = startVC
        
        if self.window?.isKeyWindow == true {
            UIView.transition(with: window!, duration: 0.2, options: .transitionCrossDissolve) {
            }
        } else {
            self.window?.makeKeyAndVisible()
        }
        
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    public static func switchToCapacitor() async {
        log.info("switchToCapacitor")
        isOnTheAir = false
        do {
            try await AccountStore.removeAllTemporaryAccounts()
        } catch {
            log.error("failed to remove all temporary accounts: \(error, .public)")
        }
        if let db {
            try! await switchStorageToCapacitor(global: GlobalStorage, db: db)
        }
        (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.switchToCapacitor()
        UIView.transition(with: window!, duration: 0.5, options: .transitionCrossDissolve) {
        } completion: { _ in
            Task {
                Api.stop()
                await WalletCoreData.clean()
                self.startVC = nil
            }
        }
    }
    
    public static func setAppIsFocused(_ isFocused: Bool) {
        guard isOnTheAir else { return }
        Task {
            // may fail at launch, which is ok
            try? await Api.setIsAppFocused(isFocused)
        }
    }
    
    public static func handle(url: URL) {
        guard isOnTheAir else { return }
        if let deeplinkHandler {
            _ = deeplinkHandler.handle(url)
        } else {
            pendingDeeplinkURL = url
        }
    }
    
    public static func handle(notification: UNNotification) {
        guard isOnTheAir else { return }
        if let deeplinkHandler {
            deeplinkHandler.handleNotification(notification)
        } else {
            pendingNotification = notification
        }
    }
}
