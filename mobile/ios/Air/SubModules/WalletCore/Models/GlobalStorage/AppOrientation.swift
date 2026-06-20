import UIKit
import WalletContext

private let appOrientationLog = Log("AppOrientation")

public enum AppOrientation {

    @MainActor public static var isLandscapeModeSettingAvailable: Bool {
        UIDevice.current.supportsOptionalLandscapeOrientation
    }

    @MainActor public static var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        if isLandscapeModeSettingAvailable && AppStorageHelper.isLandscapeModeEnabled {
            return [.portrait, .landscapeLeft, .landscapeRight]
        }
        return .portrait
    }

    @MainActor public static func updateSupportedInterfaceOrientations() {
        let mask = supportedInterfaceOrientations
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                appOrientationLog.error("requestGeometryUpdate failed: \(error, .public)")
            }
        }
    }
}
