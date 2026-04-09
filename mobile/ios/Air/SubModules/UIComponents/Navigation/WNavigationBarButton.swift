import UIKit
import WalletContext

@MainActor
public final class WNavigationBarButton {

    public let view: WButton
    public var onPress: (() -> Void)?

    public init(text: String, onPress: @escaping () -> Void) {
        let btn = Self.makeButton(text: text, icon: nil, tintColor: nil)
        self.view = btn
        self.onPress = onPress
        btn.addTarget(self, action: #selector(itemPressed), for: .touchUpInside)
    }

    public init(icon: UIImage?, tintColor: UIColor? = nil, onPress: @escaping () -> Void) {
        let btn = Self.makeButton(text: nil, icon: icon, tintColor: tintColor)
        self.view = btn
        self.onPress = onPress
        btn.addTarget(self, action: #selector(itemPressed), for: .touchUpInside)
    }

    public init(icon: UIImage?, tintColor: UIColor? = nil, menu: UIMenu) {
        let btn = Self.makeButton(text: nil, icon: icon, tintColor: tintColor)
        btn.menu = menu
        btn.showsMenuAsPrimaryAction = true
        self.view = btn
        self.onPress = nil
    }

    public func setImage(_ image: UIImage?) {
        view.setImage(image, for: .normal)
    }

    @objc private func itemPressed() {
        onPress?()
    }

    private static func makeButton(text: String?, icon: UIImage?, tintColor: UIColor?) -> WButton {
        let btn = WButton(style: .clearBackground)
        btn.setImage(icon, for: .normal)
        btn.setTitle(text, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        if let tintColor {
            btn.tintColor = tintColor
        }
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }
}

extension UIBarButtonItem {
    
    /// Legacy OS: bold localized "Done", modern OS: Blue circle checkmark
    public static func doneButtonItem(action: @escaping () -> Void) -> UIBarButtonItem {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            return UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in action() })
        }
        return legacyButtonItem(title: lang("Done"), style: .done, action: action)
    }
    
    /// Legacy OS: plain localized "Cancel", modern OS: while ellipse with a text
    public static func cancelTextButtonItem(action: @escaping () -> Void) -> UIBarButtonItem {
        let title = lang("Cancel")
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            return UIBarButtonItem(title: title, primaryAction: UIAction { _ in action() })
        }
        return legacyButtonItem(title: title, style: .done, action: action)
    }

    public static func textButtonItem(text: String, action: @escaping () -> Void) -> UIBarButtonItem {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            return UIBarButtonItem(title: text, primaryAction: UIAction { _ in action() })
        }
        return legacyButtonItem(title: text, style: .done, action: action)
    }
    
    public func asSingleItemGroup() -> UIBarButtonItemGroup {
        UIBarButtonItemGroup(barButtonItems: [self], representativeItem: nil)
    }
        
    static private func legacyButtonItem(title: String?, style: UIBarButtonItem.Style, action: @escaping () -> Void) -> UIBarButtonItem {
        let wrapper = BarButtonItemClosure(action: action)
        let item = UIBarButtonItem(
            title: title,
            style: style,
            target: wrapper,
            action: #selector(BarButtonItemClosure.invoke)
        )
        return attachWrapper(wrapper, toItem: item)
    }

    static private var closureWrapperKey = malloc(1)

    static private func attachWrapper(_ wrapper: BarButtonItemClosure, toItem item: UIBarButtonItem) -> UIBarButtonItem {
        objc_setAssociatedObject(item, &closureWrapperKey, wrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return item
    }
    
    private class BarButtonItemClosure {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func invoke() {
            action()
        }
    }
}
