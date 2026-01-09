
import UIKit

public extension UIApplication {
    
    @MainActor var connectedWindowScene: UIWindowScene? {
        for scene in connectedScenes {
            if let scene = scene as? UIWindowScene {
                return scene
            }
        }
        return nil
    }
    
    @MainActor var anySceneKeyWindow: UIWindow? {
        for scene in connectedScenes {
            if let scene = scene as? UIWindowScene, let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }
        return nil
    }

    @MainActor var sceneKeyWindow: WWindow? {
        anySceneKeyWindow as? WWindow
    }
    
    @MainActor var sceneWindows: [WWindow] {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap { $0 as? WWindow }
    }
    
}

public extension UIViewController {
    func configureSheetWithOpaqueBackground(color: UIColor) {
        if let sheet = sheetPresentationController {
            if #available(iOS 26.1, *) {
                sheet.backgroundEffect = UIColorEffect(color: color)
            }
        }
        view.backgroundColor = color
    }
}

public extension CALayer {
    func removeAllAnimationsRecursive() {
        removeAllAnimations()
        for layer in sublayers ?? [] {
            layer.removeAllAnimationsRecursive()
        }
    }
    
    func allAnimationKeysRecursive() -> [String] {
        var keys: [String] = []
        if let _keys = animationKeys(), !_keys.isEmpty {
            keys += _keys.map { "\($0) \(description)" }
        }
        for sublayer in sublayers ?? [] {
            keys += sublayer.allAnimationKeysRecursive()
        }
        return keys
    }
}
