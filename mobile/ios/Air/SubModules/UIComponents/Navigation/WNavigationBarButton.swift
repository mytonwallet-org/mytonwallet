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
