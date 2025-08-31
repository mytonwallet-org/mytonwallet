//
//  AppDelegate.swift
//  MTW Pure Air
//
//  Created by nikstar on 18.05.2025.
//

import UIKit
import AirAsFramework
import UIComponents
import WalletCore
import WalletContext

private let log = Log("PureAir-AppDelegate")

@main
class AppDelegate: UIResponder, UIApplicationDelegate, MtwAppDelegateProtocol {
    
    var window: UIWindow?
    
    private var backgroundCover: UIView?
    
    private var isOnTheAir: Bool {
        return true
    }
    
    func switchToAir() {
        startTheApp()
    }
    
    func switchToCapacitor() {
        startTheApp()
    }
    
    func showDebugView() {
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        log.info("**** APP START **** \(Date().formatted(.iso8601), .public)")
        
        let window = UIWindow()
        window.rootViewController = SharedSplashVC()
        window.makeKeyAndVisible()
        self.window = window
        AirLauncher.set(window: window)
        
        launchApp()
        return true
    }
    
    func launchApp() {
        startTheApp()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        log.info("applicationWillResignActive")
        AirLauncher.willResignActive()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        log.info("applicationDidEnterBackground")
        LogStore.shared.syncronize()
        AirLauncher.setAppIsFocused(false)
        if isOnTheAir, AutolockStore.shared.autolockOption != .never {
            if let window, self.backgroundCover == nil {
                let view = WBlurView()
                view.translatesAutoresizingMaskIntoConstraints = false
                //                view.backgroundColor = WTheme.tint.withAlphaComponent(0.5)
                window.addSubview(view)
                view.frame = window.bounds
                self.backgroundCover = view
            }
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        log.info("applicationWillEnterForeground")
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
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        log.info("applicationWillEnterForeground")
        AirLauncher.willBecomeActive()
        if let view = self.backgroundCover {
            UIView.animate(withDuration: 0.15) {
                view.alpha = 0
            } completion: { _ in
                view.removeFromSuperview()
                self.backgroundCover = nil
            }
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        LogStore.shared.syncronize()
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        
        if isOnTheAir {
            log.info("open url=\(url)")
            AirLauncher.handle(url: url)
            return true
        }
        
        return false
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        if isOnTheAir {
            guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
                  let url = userActivity.webpageURL else {
                return false
            }
            log.info("continue user activity url=\(url)")
            AirLauncher.handle(url: url)
            return true
        }
        
        return false
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
}
