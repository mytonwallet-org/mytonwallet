
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
    
    @MainActor var sceneKeyWindow: WWindow? {
        for scene in connectedScenes {
            if let scene = scene as? UIWindowScene, let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow as? WWindow
            }
        }
        return nil
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
