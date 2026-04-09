//
//  AirLauncher.swift
//  AirAsFramework
//
//  Created by Sina on 9/5/24.
//

import Foundation
import UIKit
import UIAgent
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
                return UserDefaults.standard.object(forKey: "isOnAir") as? Bool ?? DEFAULT_TO_AIR
            } else {
                UserDefaults.standard.set(true, forKey: "isOnAir")
                return true
            }
        }
        set {
            if canSwitchToCapacitor {
                UserDefaults.standard.set(newValue, forKey: "isOnAir")
            } else {
                UserDefaults.standard.set(true, forKey: "isOnAir")
            }
        }
    }
    
    private static var window: WWindow!
    private static var runtimeCoordinator: AirRuntimeCoordinator? {
        didSet {
            guard let runtimeCoordinator else { return }
            if let pendingDeeplinkURL {
                _ = runtimeCoordinator.handle(url: pendingDeeplinkURL)
                self.pendingDeeplinkURL = nil
            }
            if let pendingNotification {
                runtimeCoordinator.handle(notification: pendingNotification)
                self.pendingNotification = nil
            }
        }
    }

    private static var db: (any DatabaseWriter)?
    private static var hasStartedDeferredLaunch = false
    static var pendingDeeplinkURL: URL? = nil
    static var pendingNotification: UNNotification? = nil
    static var pendingPushToken: String? = nil
    static var appUnlocked = false
    private static var hasStartedWalletCore = false
    
    public static func set(window: WWindow) {
        AirLauncher.window = window
        StartupTrace.mark("airLauncher.window.set")
    }

    public static func installRootViewControllerIfNeeded() {
        guard let window else { return }
        RootStateCoordinator.shared.installAsRootViewController(on: window, animationDuration: nil)
    }
    
    public static func soarIntoAir() async {
        log.info("soarIntoAir")
        StartupTrace.beginInterval("airLauncher.soarIntoAir")
        StartupTrace.mark("airLauncher.soarIntoAir.begin")
        hasStartedWalletCore = false
        hasStartedDeferredLaunch = false
        appUnlocked = false
        runtimeCoordinator?.reset()
        runtimeCoordinator = nil
        RootStateCoordinator.shared.reset()
        AgentStore.shared.clean()
        installRootViewControllerIfNeeded()

        let launchPreparation: DatabaseBootstrapResult
        do {
            launchPreparation = try await DatabaseBootstrap.prepare()
        } catch {
            StartupTrace.endInterval("airLauncher.soarIntoAir", details: "result=failed.bootstrap")
            await presentStartupFailure(error, phase: .databaseBootstrap)
            return
        }
        let db = launchPreparation.db
        self.db = db
        WalletCore.db = db
        
        configureAppActions()
        StartupTrace.mark("airLauncher.appActions.configured")
        AppStorageHelper.reset()
        StartupTrace.mark("airLauncher.appStorage.reset")
        do {
            try await WalletCoreData.startMinimal(
                db: db,
                bootstrapAccountCountHint: launchPreparation.databaseAccountCount
            )
        } catch {
            StartupTrace.endInterval("airLauncher.soarIntoAir", details: "result=failed.walletCoreMinimal")
            await presentStartupFailure(error, phase: .walletCoreBootstrap)
            return
        }
        StartupTrace.mark("airLauncher.walletCoreData.minimal.end")

        let isFirstLaunch = (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.isFirstLaunch == true
        if isFirstLaunch && AccountStore.accountsById.isEmpty && launchPreparation.shouldDeletePreviousInstallAccountsOnFirstLaunch {
            log.info("Deleting accounts from previous install")
            KeychainHelper.deleteAccountsFromPreviousInstall()
        }
        
        UIView.setAnimationsEnabled(AppStorageHelper.animations)
        
        let nightMode = AppStorageHelper.activeNightMode
        window?.overrideUserInterfaceStyle = nightMode.userInterfaceStyle
        installCurrentAccountTheme()
        window?.updateTheme()
        StartupTrace.mark("airLauncher.theme.ready", details: "nightMode=\(String(describing: nightMode)) animations=\(AppStorageHelper.animations)")

        let runtimeCoordinator = AirRuntimeCoordinator()
        self.runtimeCoordinator = runtimeCoordinator
        runtimeCoordinator.beginLaunch()
        DispatchQueue.main.async {
            runtimeCoordinator.start()
        }
        Task { @MainActor in
            await finishDeferredLaunch()
        }
        StartupTrace.mark("airLauncher.window.rootSet")

        if self.window?.isKeyWindow != true {
            self.window?.makeKeyAndVisible()
        }
        StartupTrace.mark("airLauncher.window.visible")
        StartupTrace.endInterval("airLauncher.soarIntoAir")
    }

    static func finishDeferredLaunch() async {
        guard !hasStartedDeferredLaunch else { return }
        guard let db else { return }
        hasStartedDeferredLaunch = true

        await WalletCoreData.startDeferred(db: db)
        AgentStore.shared.start()
        StartupTrace.mark("airLauncher.walletCoreData.start.end")
        hasStartedWalletCore = true
        if let pendingPushToken {
            AccountStore.didRegisterForPushNotifications(userToken: pendingPushToken)
            self.pendingPushToken = nil
        }
        installCurrentAccountTheme()
        window?.updateTheme()

        UIApplication.shared.registerForRemoteNotifications()
        StartupTrace.mark("airLauncher.remoteNotifications.requested")
        runtimeCoordinator?.walletCoreBootstrapDidFinish()
    }

    private static func presentStartupFailure(_ error: any Error, phase: StartupFailurePhase) async {
        hasStartedDeferredLaunch = false
        hasStartedWalletCore = false
        await StartupFailureManager.handle(error, phase: phase) {
            Task { @MainActor in
                await AirLauncher.soarIntoAir()
            }
        }
    }

    private static func installCurrentAccountTheme() {
        let accountId = AccountStore.accountId ?? ""
        @Dependency(\.accountSettings) var _accountSettings
        let activeColorTheme = _accountSettings.for(accountId: accountId).accentColorIndex
        changeThemeColors(to: activeColorTheme)
        StartupTrace.mark("airLauncher.theme.account.ready", details: "accent=\(String(describing: activeColorTheme))")
    }
    
    public static func switchToCapacitor() async {
        log.info("switchToCapacitor")
        do {
            try await AccountStore.removeAllTemporaryAccounts()
        } catch {
            log.error("failed to remove all temporary accounts: \(error, .public)")
        }

        guard let db else {
            log.error("failed to switch to capacitor: database is unavailable")
            AppActions.showError(error: DisplayError(text: "Unable to switch to Classic app."))
            return
        }

        do {
            try await DatabaseBootstrap.exportStateToCapacitor(db: db)
        } catch {
            log.error("failed to export state before switching to capacitor: \(error, .public)")
            AppActions.showError(error: DisplayError(text: capacitorSwitchErrorMessage(for: error)))
            return
        }

        isOnTheAir = false
        hasStartedWalletCore = false
        (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.switchToCapacitor()
        UIView.transition(with: window!, duration: 0.5, options: .transitionCrossDissolve) {
        } completion: { _ in
            Task {
                Api.stop()
                AgentStore.shared.resetConversation()
                await WalletCoreData.clean()
                AgentStore.shared.clean()
                self.runtimeCoordinator?.reset()
                self.runtimeCoordinator = nil
                WalletContextManager.delegate = nil
                RootStateCoordinator.shared.reset()
            }
        }
    }

    private static func capacitorSwitchErrorMessage(for error: any Error) -> String {
        if let storageDetails = StartupFailureDiagnostics.webViewStorageDetails(error),
           storageDetails.localizedCaseInsensitiveContains("quotaexceeded") {
            return "Unable to switch to Classic app because browser storage is full."
        }
        return "Unable to switch to Classic app."
    }
    
    public static func setAppIsFocused(_ isFocused: Bool) {
        guard isOnTheAir else { return }
        Task {
            try? await Api.setIsAppFocused(isFocused)
        }
    }
    
    public static func handle(url: URL) {
        guard isOnTheAir else { return }
        if let runtimeCoordinator {
            _ = runtimeCoordinator.handle(url: url)
        } else {
            pendingDeeplinkURL = url
        }
    }
    
    public static func handle(notification: UNNotification) {
        guard isOnTheAir else { return }
        if let runtimeCoordinator {
            runtimeCoordinator.handle(notification: notification)
        } else {
            pendingNotification = notification
        }
    }

    public static func didRegisterForPushNotifications(userToken: String) {
        guard isOnTheAir else { return }
        guard hasStartedWalletCore else {
            pendingPushToken = userToken
            return
        }
        AccountStore.didRegisterForPushNotifications(userToken: userToken)
    }

    static func lockApp(animated: Bool) {
        runtimeCoordinator?.lockApp(animated: animated)
    }
}
