import UIKit
import Capacitor
import AirAsFramework
import MytonwalletAirAppLauncher
import MytonwalletNativeBottomSheet
import FirebaseCore
import FirebaseMessaging
import WalletContext
import UIComponents
import SwiftKeychainWrapper
import WalletCore

private let log = Log("AppDelegate")


class AppDelegate: UIResponder, UIApplicationDelegate, @preconcurrency MTWAirToggleDelegate, MtwAppDelegateProtocol {
    
    private var isOnTheAir: Bool {
        return AirLauncher.isOnTheAir
    }

    private func clean(webView: WKWebView?) {
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
    }
    
    private func cleanWebViews() {
        if let window = UIApplication.shared.connectedSceneDelegate?.window,
           let capBridgeVC = window.rootViewController as? CAPBridgeViewController,
           let bottomSheetPlugin = capBridgeVC.bridge?.plugin(withName: "BottomSheet") as? BottomSheetPlugin {
            self.clean(webView: bottomSheetPlugin.capWebView)
            self.clean(webView: capBridgeVC.webView)
        }
    }

    @MainActor func switchToAir() {
        cleanWebViews()
        UIApplication.shared.connectedSceneDelegate?.switchToAir()
    }
    
    @MainActor func switchToCapacitor() {
        UIApplication.shared.connectedSceneDelegate?.switchToCapacitor()
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logAppStart()
        
        if application.isProtectedDataAvailable {
            let isFirstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date == nil
            if isFirstLaunch {
                UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
            }
        }
        
        FirebaseApp.configure()
        
        guard application.isProtectedDataAvailable else {
            log.error("application.isProtectedDataAvailable = false")
            LogStore.shared.syncronize()
            return false
        }
        
        congigureIOS26Compativility()

        return true
    }

    func showDebugView() {
        _showDebugView()
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if isOnTheAir {
            AirLauncher.handle(url: url)
            return true
        }
        
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        LogStore.shared.syncronize()
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

        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token(completion: { (token, error) in
            if let error = error {
                log.error("capacitorDidFailToRegisterForRemoteNotifications \(error, .public)")
                NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
            } else if let token = token {
                log.info("capacitorDidRegisterForRemoteNotifications")
                NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: token)
                if self.isOnTheAir, GlobalStorage.globalDict != nil {
                    AccountStore.didRegisterForPushNotifications(userToken: token)
                }
            }
        })
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("didFailToRegisterForRemoteNotificationsWithError \(error, .public)")
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
}

func logAppStart() {
    let infoDict = Bundle.main.infoDictionary
    let appVersion = infoDict?["CFBundleShortVersionString"] as? String ?? "unknown"
    let buildNumber = infoDict?["CFBundleVersion"] as? String ?? "unknown"
    let deviceModel = UIDevice.current.model
    let systemVersion = UIDevice.current.systemVersion
    _ = appStart
    log.info("**** APP START **** \(Date().formatted(.iso8601), .public) version=\(appVersion, .public) build=\(buildNumber, .public) device=\(deviceModel, .public) iOS=\(systemVersion, .public)")
}
