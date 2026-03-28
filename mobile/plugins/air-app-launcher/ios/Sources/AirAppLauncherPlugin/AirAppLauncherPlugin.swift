import Foundation
import Capacitor
import WidgetKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(AirAppLauncherPlugin)
public class AirAppLauncherPlugin: CAPPlugin, CAPBridgedPlugin {
    private let selectedLanguageCodeKey = "selectedLanguageCode"
    private let appGroupId = "group.org.mytonwallet.app"

    public let identifier = "AirAppLauncherPlugin"
    public let jsName = "AirAppLauncher"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "switchToAir", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLanguage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setBaseCurrency", returnType: CAPPluginReturnPromise)
    ]

    @objc public func switchToAir(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            (UIApplication.shared.delegate as? MTWAirToggleDelegate)?.switchToAir()
        }
    }
    @objc public func setLanguage(_ call: CAPPluginCall) {
        guard let langCode = call.getString("langCode"), !langCode.isEmpty else {
            call.reject("langCode is required")
            return
        }

        UserDefaults.standard.set(langCode, forKey: selectedLanguageCodeKey)
        UserDefaults.standard.set([langCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        let appGroupDefaults = UserDefaults(suiteName: appGroupId)
        appGroupDefaults?.set(langCode, forKey: selectedLanguageCodeKey)
        appGroupDefaults?.synchronize()

        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        call.resolve()
    }
    @objc public func setBaseCurrency(_ call: CAPPluginCall) {
    }
}
