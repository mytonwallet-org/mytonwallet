import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(AirAppLauncherPlugin)
public class AirAppLauncherPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AirAppLauncherPlugin"
    public let jsName = "AirAppLauncher"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "switchToAir", returnType: CAPPluginReturnPromise)
    ]

    @objc public func switchToAir(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            (UIApplication.shared.delegate as? MTWAirToggleDelegate)?.switchToAir()
        }
    }
}
