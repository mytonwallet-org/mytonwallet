import UIKit
import AirAsFramework
import WalletContext
import UIComponents
import WalletCore
import FirebaseCore
import FirebaseMessaging
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

private let log = Log("AppDelegate")

final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logAppStart()
        StartupTrace.reset(flow: "process-launch", origin: appStart)
        StartupTrace.beginInterval("startup.toHomeVisible")
        StartupTrace.beginInterval("startup.toHomeReady")
        StartupTrace.beginInterval("startup.toPresentUnlock")
        StartupTrace.mark("appDelegate.didFinishLaunching.begin")
        
        if application.isProtectedDataAvailable {
            AirLauncher.recordLaunchMetadata()
        }

        StartupTrace.mark(
            "appDelegate.launchMetadata.ready",
            details: "protectedData=\(application.isProtectedDataAvailable) firstLaunch=\(AirLauncher.isFirstLaunch)"
        )
        
        FirebaseApp.configure()
        installCrashlyticsReporter()
        StartupTrace.mark("appDelegate.firebase.configure")

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-testCrashlyticsFault") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                log.fault("Crashlytics test fault")
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-testCrashlyticsFatalCrash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                fatalError("Crashlytics test fatal crash")
            }
        }
        #endif
        
        guard application.isProtectedDataAvailable else {
            log.error("application.isProtectedDataAvailable = false")
            StartupTrace.mark("appDelegate.didFinishLaunching.abort", details: "protectedDataUnavailable")
            LogStore.shared.syncronize()
            return false
        }
        
        StartupTrace.mark("appDelegate.didFinishLaunching.end")
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AirLauncher.handle(url: url)
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        LogStore.shared.syncronize()
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            AppOrientation.supportedInterfaceOrientations
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        log.info("continue user activity url=\(url)")
        AirLauncher.handle(url: url)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token(completion: { (token, error) in
            if let error = error {
                log.error("didFailToRegisterForRemoteNotifications \(error, .public)")
            } else if let token = token {
                log.info("didRegisterForRemoteNotifications")
                Task { @MainActor in
                    AirLauncher.didRegisterForPushNotifications(userToken: token)
                }
            }
        })
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("didFailToRegisterForRemoteNotificationsWithError \(error, .public)")
    }
    
}

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

private func installCrashlyticsReporter() {
    #if canImport(FirebaseCrashlytics)
    Log.setFaultReporter { event in
        let source = "\(event.fileID):\(event.line)"
        let message = String(event.message.prefix(1_024))
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("[\(event.category)] \(source) \(message)")
        crashlytics.record(
            error: NSError(
                domain: "org.mytonwallet.air.log.fault",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "\(event.category) fault at \(source)",
                    "category": event.category,
                    "file": event.fileID,
                    "function": event.function,
                    "line": event.line,
                    "message": message,
                ]
            )
        )
    }
    #endif
}
