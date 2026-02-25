import UIKit
import AirAsFramework
import WalletContext
import UIComponents
import WalletCore
import WebKit
#if canImport(Capacitor)
import Capacitor
import MytonwalletAirAppLauncher
import FirebaseCore
import FirebaseMessaging
import SwiftKeychainWrapper
#endif

private let log = Log("AppDelegate")

final class AppDelegate: UIResponder, UIApplicationDelegate, MtwAppDelegateProtocol {
    
    #if canImport(Capacitor)
    public let canSwitchToCapacitor = true
    #else
    public let canSwitchToCapacitor = false
    #endif
    
    public var isFirstLaunch: Bool = false
    
    private var isOnTheAir: Bool {
        return AirLauncher.isOnTheAir
    }

    private func clean(webView: WKWebView?) {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
    }
    
    func switchToAir() {
        cleanWebViews()
        clearCapacitorLaunchUrlCache()
        UIApplication.shared.connectedSceneDelegate?.switchToAir()
    }
    
    func switchToCapacitor() {
        UIApplication.shared.connectedSceneDelegate?.switchToCapacitor()
    }
    
    private func cleanWebViews() {
         #if canImport(Capacitor)
        if let window = UIApplication.shared.connectedSceneDelegate?.window,
           let capBridgeVC = window.rootViewController as? CAPBridgeViewController {
            self.clean(webView: capBridgeVC.webView)
        }
        #endif
    }

    private func clearCapacitorLaunchUrlCache() {
        #if canImport(Capacitor)
        let applicationDelegateProxy = ApplicationDelegateProxy.shared
        if applicationDelegateProxy.lastURL != nil {
            _ = applicationDelegateProxy.application(UIApplication.shared, open: URL(string: "about:blank")!)
        }
        #endif
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logAppStart()
        
        if application.isProtectedDataAvailable {
            let isFirstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date == nil
            if isFirstLaunch {
                log.info("firstLaunchDate key not found")
                UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
                UserDefaults.standard.set(appVersion, forKey: "firstLaunchVersion")
                
                if isDefinitelyNotAPreexistingInstall() {
                    log.info("isDefinitelyNotAPreexistingInstall returned true, switching to Air")
                    AirLauncher.isOnTheAir = true
                    self.isFirstLaunch = true
                }
            }
            
            UserDefaults.standard.set(Date(), forKey: "lastLaunchDate")
            UserDefaults.standard.set(appVersion, forKey: "lastLaunchVersion")
        }
        
        #if canImport(Capacitor)
        FirebaseApp.configure()
        #endif
        
        guard application.isProtectedDataAvailable else {
            log.error("application.isProtectedDataAvailable = false")
            LogStore.shared.syncronize()
            return false
        }
        
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
    
    /// double check for app installs not opened since `firstLaunchDate` key was introduced
    private func isDefinitelyNotAPreexistingInstall() -> Bool {
        do {
            func isEmpty(_ url: URL) -> Bool {
                let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [])
                return (contents ?? []).isEmpty
            }
            if isEmpty(.documentsDirectory) && isEmpty(.cachesDirectory.appending(path: "WebKit", directoryHint: .isDirectory)) {
                return true
            } else {
                log.info("isDefinitelyNotAPreexistingInstall check returned false")
                let documents = try FileManager.default.contentsOfDirectory(at: .documentsDirectory, includingPropertiesForKeys: [])
                let caches = try FileManager.default.contentsOfDirectory(at: .cachesDirectory, includingPropertiesForKeys: [])
                log.info("documents=\(documents, .public)")
                log.info("caches=\(caches, .public)")
            }
        } catch {
            log.error("failed to check if pre-existing install: \(error, .public)")
        }
        return false
    }
}

#if canImport(Capacitor)
extension AppDelegate: @preconcurrency MTWAirToggleDelegate {
}
#endif


private func logAppStart() {
    let infoDict = Bundle.main.infoDictionary
    let buildNumber = infoDict?["CFBundleVersion"] as? String ?? "unknown"
    let deviceModel = UIDevice.current.model
    let systemVersion = UIDevice.current.systemVersion
    _ = appStart
    log.info("**** APP START **** \(Date().formatted(.iso8601), .public) version=\(appVersion, .public) build=\(buildNumber, .public) device=\(deviceModel, .public) iOS=\(systemVersion, .public)")
}

private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
}
