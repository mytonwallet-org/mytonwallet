import UIKit
import AirAsFramework
import WalletContext
import UIComponents
import WalletCore
import WebKit
#if canImport(Capacitor)
import Capacitor
import MytonwalletAirAppLauncher
import MytonwalletNativeBottomSheet
import FirebaseCore
import FirebaseMessaging
import SwiftKeychainWrapper
#endif

private let log = Log("AppDelegate")


class AppDelegate: UIResponder, UIApplicationDelegate, MtwAppDelegateProtocol {
    
    #if canImport(Capacitor)
    public let canSwitchToCapacitor = true
    #else
    public let canSwitchToCapacitor = false
    #endif

    
    private var isOnTheAir: Bool {
        return AirLauncher.isOnTheAir
    }

    private func clean(webView: WKWebView?) {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
    }
    
    private func cleanWebViews() {
         #if canImport(Capacitor)
        if let window = UIApplication.shared.connectedSceneDelegate?.window,
           let capBridgeVC = window.rootViewController as? CAPBridgeViewController,
           let bottomSheetPlugin = capBridgeVC.bridge?.plugin(withName: "BottomSheet") as? BottomSheetPlugin {
            self.clean(webView: bottomSheetPlugin.capWebView)
            self.clean(webView: capBridgeVC.webView)
        }
        #endif
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
        
        #if canImport(Capacitor)
        FirebaseApp.configure()
        #endif
        
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
        #if canImport(Capacitor)
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
        #else
        fatalError()
        #endif
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
        
        #if canImport(Capacitor)
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
        #else
        fatalError()
        #endif
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(Capacitor)
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
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if canImport(Capacitor)
        log.error("didFailToRegisterForRemoteNotificationsWithError \(error, .public)")
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
        #endif
    }
}

#if canImport(Capacitor)
extension AppDelegate: @preconcurrency MTWAirToggleDelegate {
}
#endif


func logAppStart() {
    let infoDict = Bundle.main.infoDictionary
    let appVersion = infoDict?["CFBundleShortVersionString"] as? String ?? "unknown"
    let buildNumber = infoDict?["CFBundleVersion"] as? String ?? "unknown"
    let deviceModel = UIDevice.current.model
    let systemVersion = UIDevice.current.systemVersion
    _ = appStart
    log.info("**** APP START **** \(Date().formatted(.iso8601), .public) version=\(appVersion, .public) build=\(buildNumber, .public) device=\(deviceModel, .public) iOS=\(systemVersion, .public)")
}
