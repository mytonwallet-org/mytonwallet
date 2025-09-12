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

fileprivate let blurredUIEnabled = false

private let log = Log("AirLauncher")


public class AirLauncher {

    public static var isOnTheAir: Bool {
        get { UserDefaults.standard.object(forKey: "isOnAir") as? Bool ?? DEFAULT_TO_AIR }
        set { UserDefaults.standard.set(newValue, forKey: "isOnAir") }
    }
    private static var window: WWindow!
    private static var startVC: SplashVC?
    
    private static var db: (any DatabaseWriter)?
    
    static var deeplinkHandler: DeeplinkHandler? = nil {
        didSet {
            if let pendingDeeplinkURL {
                deeplinkHandler?.handle(pendingDeeplinkURL)
                AirLauncher.pendingDeeplinkURL = nil
            }
        }
    }
    static var pendingDeeplinkURL: URL? = nil
    static var appUnlocked = false
    static var registeredFonts = false
    
    public static func set(window: WWindow) {
        AirLauncher.window = window
    }
    
    @MainActor public static func soarIntoAir() async {
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
        
        // TODO: Detect if this is new install and delete old keychain storage if needed
        // if database has no accounts but keychain does, these accounts come from previous install and must be deleted
        
        configureAppActions()
        // Prepare storage
        AppStorageHelper.reset()
        await WalletCoreData.start(db: db)

        if !registeredFonts {
            registeredFonts = true
            UIFont.registerAirFonts()
        }
        
        // Load theme
        let activeColorTheme = AccountStore.currentAccountAccentColorIndex
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
    
    @MainActor public static func switchToCapacitor() async {
        log.info("switchToCapacitor")
        isOnTheAir = false
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
        if !isOnTheAir {
            return
        }
        Task {
            do {
                try await Api.setIsAppFocused(isFocused)
            } catch {
                log.error("setIsAppFocused: \(error, .public)")
            }
        }
    }
    
    public static func handle(url: URL) {
        if !isOnTheAir {
            return
        }
        if let deeplinkHandler {
            deeplinkHandler.handle(url)
        } else {
            pendingDeeplinkURL = url
        }
    }
    
    public static func willResignActive() {
        if !isOnTheAir {
            return
        }

        guard appUnlocked else {
            return
        }

        if blurredUIEnabled {
            let blurEffect = UIBlurEffect(style: .prominent)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            blurEffectView.frame = window!.frame
            blurEffectView.tag = 2024
            
            window?.addSubview(blurEffectView)
        }
    }
    
    public static func willBecomeActive() {
        if !isOnTheAir {
            return
        }

        if blurredUIEnabled {
            if let blurView = window?.viewWithTag(2024) {
                UIView.animate(withDuration: 0.3) {
                    blurView.alpha = 0
                } completion: { _ in
                    blurView.removeFromSuperview()
                }
            }
        }
    }
    
    public static var isCapacitorAppAvailable: Bool {
        true
    }
}
