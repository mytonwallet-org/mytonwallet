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

private let firstLaunchDateKey = "firstLaunchDate"
private let firstLaunchVersionKey = "firstLaunchVersion"
private let lastLaunchDateKey = "lastLaunchDate"
private let lastLaunchVersionKey = "lastLaunchVersion"


@MainActor
public class AirLauncher {
    private static var window: WWindow!
    // Long-lived: queues incoming deeplinks/notifications/system actions until the wallet
    // is ready and unlocked, including those arriving before `soarIntoAir` has run.
    private static let runtimeCoordinator = AirRuntimeCoordinator()

    private static var db: (any DatabaseWriter)?
    private static var hasStartedDeferredLaunch = false
    static var pendingPushToken: String? = nil
    static var appUnlocked = false
    private static var hasStartedWalletCore = false
    public private(set) static var isFirstLaunch = false

    public static func recordLaunchMetadata() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: firstLaunchDateKey) as? Date == nil {
            log.info("firstLaunchDate key not found")
            defaults.set(Date(), forKey: firstLaunchDateKey)
            defaults.set(appVersion, forKey: firstLaunchVersionKey)
            isFirstLaunch = true
        }
        defaults.set(Date(), forKey: lastLaunchDateKey)
        defaults.set(appVersion, forKey: lastLaunchVersionKey)
    }

    public static func launch(window: WWindow) {
        AirLauncher.window = window
        StartupTrace.mark("airLauncher.window.set")
        installRootViewControllerIfNeeded()
        Task(priority: .userInitiated) {
            await soarIntoAir()
        }
    }

    static func installRootViewControllerIfNeeded() {
        guard let window else { return }
        RootStateCoordinator.shared.installAsRootViewController(on: window, animationDuration: nil)
    }

    static func soarIntoAir() async {
        log.info("soarIntoAir")
        StartupTrace.beginInterval("airLauncher.soarIntoAir")
        StartupTrace.mark("airLauncher.soarIntoAir.begin")
        hasStartedWalletCore = false
        hasStartedDeferredLaunch = false
        appUnlocked = false
        runtimeCoordinator.reset()
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

        let runtimeCoordinator = self.runtimeCoordinator
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
        await runtimeCoordinator.walletCoreBootstrapDidFinish()
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
    
    public static func setAppIsFocused(_ isFocused: Bool) {
        Task {
            try? await Api.setIsAppFocused(isFocused)
        }
    }
    
    public static func handle(url: URL) {
        _ = runtimeCoordinator.handle(url: url)
    }

    public static func handle(notification: UNNotification) {
        runtimeCoordinator.handle(notification: notification)
    }

    public static func handle(systemAction: AirSystemAction) {
        runtimeCoordinator.handle(systemAction: systemAction)
    }

    public static func didRegisterForPushNotifications(userToken: String) {
        guard hasStartedWalletCore else {
            pendingPushToken = userToken
            return
        }
        AccountStore.didRegisterForPushNotifications(userToken: userToken)
    }

    static func lockApp(animated: Bool) {
        runtimeCoordinator.lockApp(animated: animated)
    }
}
