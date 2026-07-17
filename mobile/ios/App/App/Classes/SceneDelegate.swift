//
//  SceneDelegate.swift
//  App
//
//  Created by nikstar on 02.07.2025.
//

import AirAsFramework
import UIKit
import UIComponents
import WalletCore
import WalletContext
import WidgetKit

private let log = Log("SceneDelegate")

@MainActor
final class SceneDelegate: UIResponder, UISceneDelegate, UIWindowSceneDelegate {
    
    var window: WWindow?
    private var backgroundCover: UIView?
    private var pendingShortcutItem: UIApplicationShortcutItem?

    // MARK: Lifecycle
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        StartupTrace.mark("sceneDelegate.willConnect.begin", details: summarize(connectionOptions))
        
        guard let windowScene = scene as? UIWindowScene else {
            StartupTrace.mark("sceneDelegate.willConnect.abort", details: "windowScene=nil")
            return
        }
        
        let window = WWindow(windowScene: windowScene)
        self.window = window

        AirLauncher.launch(window: window)
        window.makeKeyAndVisible()
        StartupTrace.mark("sceneDelegate.window.ready")
        StartupTrace.mark("sceneDelegate.airLauncher.launched")
        
        if let shortcutItem = connectionOptions.shortcutItem {
            pendingShortcutItem = shortcutItem
        } else if let userActivity = connectionOptions.userActivities.first, userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            handleUrl(url)
        } else if let urlContext = connectionOptions.urlContexts.first {
            handleUrl(urlContext.url)
        } else if let notificationResponse = connectionOptions.notificationResponse {
            handleNotification(notificationResponse)
        }
        
        StartupTrace.mark("sceneDelegate.willConnect.end")
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        log.info("sceneWillResignActive")

        HomeScreenQuickAction.updateShortcutItems()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        if let url = urlContexts.first?.url {
            handleUrl(url)
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            handleUrl(url)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        return handleShortcutItem(shortcutItem)
    }
    
    private func handleUrl(_ url: URL) {
        AirLauncher.handle(url: url)
    }

    private func handleNotification(_ notificationResponse: UNNotificationResponse) {
        AirLauncher.handle(notification: notificationResponse.notification)
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        log.info("sceneDidEnterBackground")
        LogStore.shared.syncronize()
        AirLauncher.setAppIsFocused(false)
        if AutolockStore.shared.autolockOption != .never {
            if let window, self.backgroundCover == nil {
                let view = WBlurView()
                view.translatesAutoresizingMaskIntoConstraints = false
                window.addSubview(view)
                view.frame = window.bounds
                self.backgroundCover = view
            }
        }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        log.info("sceneWillEnterForeground")
        AirLauncher.setAppIsFocused(true)
        if let view = self.backgroundCover {
            UIView.animate(withDuration: 0.15) {
                view.alpha = 0
            } completion: { _ in
                view.removeFromSuperview()
                self.backgroundCover = nil
            }
        }
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        log.info("sceneDidBecomeActive")
        
        if let view = self.backgroundCover {
            UIView.animate(withDuration: 0.15) {
                view.alpha = 0
            } completion: { _ in
                view.removeFromSuperview()
                self.backgroundCover = nil
            }
        }

        if let pendingShortcutItem {
            self.pendingShortcutItem = nil
            _ = handleShortcutItem(pendingShortcutItem)
        }
    }
    
    @discardableResult
    private func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        HomeScreenQuickAction.handle(shortcutItem)
    }

    private func summarize(_ connectionOptions: UIScene.ConnectionOptions) -> String {
        "urlContexts=\(connectionOptions.urlContexts.count) userActivities=\(connectionOptions.userActivities.count) notificationResponse=\(connectionOptions.notificationResponse != nil) shortcutItem=\(connectionOptions.shortcutItem != nil)"
    }
}
