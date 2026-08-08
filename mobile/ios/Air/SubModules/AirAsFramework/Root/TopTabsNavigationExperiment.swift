import Foundation
import WalletContext

enum TopTabsNavigationExperiment {
    enum Variant: String, CaseIterable, Identifiable {
        case disabled
        case navigationBar

        var id: Self { self }

        var title: String {
            switch self {
            case .disabled:
                "Off"
            case .navigationBar:
                "Navigation Bar"
            }
        }

        var isEnabled: Bool { self != .disabled }
    }

    static let variantUserDefaultsKey = "experimental_topTabsRootNavigationVariant"
    static let didChangeNotification = Notification.Name("TopTabsNavigationExperimentDidChange")

    static var variant: Variant {
        guard IS_DEBUG_OR_TESTFLIGHT_DEFAULT else { return .disabled }
        guard let rawValue = UserDefaults.standard.string(forKey: variantUserDefaultsKey),
              let variant = Variant(rawValue: rawValue) else {
            return .disabled
        }
        return variant
    }

    static var initialVariantRawValue: String {
        variant.rawValue
    }

    static var isEnabled: Bool {
        variant.isEnabled
    }

    static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

enum DrawerCloseControlExperiment {
    enum Variant: String, CaseIterable, Identifiable {
        case closeButton
        case currentTabTitle

        var id: Self { self }

        var title: String {
            switch self {
            case .closeButton:
                "Standard Close Button"
            case .currentTabTitle:
                "Current Tab Title"
            }
        }
    }

    static let variantUserDefaultsKey = "experimental_drawerCloseControlVariant"
    static let didChangeNotification = Notification.Name("DrawerCloseControlExperimentDidChange")

    static var variant: Variant {
        guard IS_DEBUG_OR_TESTFLIGHT_DEFAULT else { return .closeButton }
        guard let rawValue = UserDefaults.standard.string(forKey: variantUserDefaultsKey),
              let variant = Variant(rawValue: rawValue) else {
            return .closeButton
        }
        return variant
    }

    static var initialVariantRawValue: String {
        variant.rawValue
    }

    static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
