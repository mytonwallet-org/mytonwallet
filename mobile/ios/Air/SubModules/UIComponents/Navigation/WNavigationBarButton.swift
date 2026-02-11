import UIKit
import WalletContext

public class WNavigationBarButton {

    public let view: UIView
    public var onPress: (() -> Void)?

    public init(text: String? = nil, icon: UIImage? = nil, tintColor: UIColor? = nil, onPress: (() -> Void)? = nil, menu: UIMenu? = nil, showsMenuAsPrimaryAction: Bool = false) {
        let btn = {
            let btn = WButton(style: .clearBackground)
            btn.setImage(icon, for: .normal)
            btn.setTitle(text, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            if let tintColor {
                btn.tintColor = tintColor
            }
            if icon != nil, text != nil {
                btn.configuration?.imagePadding = 8
            }
            btn.translatesAutoresizingMaskIntoConstraints = false
            return btn
        }()
        if let menu {
            btn.menu = menu
            btn.showsMenuAsPrimaryAction = showsMenuAsPrimaryAction
        }
        self.view = btn
        self.onPress = onPress

        if !showsMenuAsPrimaryAction {
            btn.addTarget(self, action: #selector(itemPressed), for: .touchUpInside)
        }
    }

    public init(view: UIView, onPress: (() -> Void)? = nil) {
        self.view = view
        self.onPress = onPress
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemPressed)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func itemPressed() {
        onPress?()
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

