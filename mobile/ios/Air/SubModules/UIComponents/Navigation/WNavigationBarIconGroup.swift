import UIKit

@MainActor
public final class WNavigationBarIconGroup {

    @MainActor
    public final class Item {
        fileprivate let button: UIButton
        private let actionProxy: ActionProxy

        public init(
            title: String,
            accessibilityLabel: String? = nil,
            image: UIImage?,
            onPress: @escaping () -> Void
        ) {
            let resolvedAccessibilityLabel = accessibilityLabel ?? title
            let renderedImage = Self.renderedImage(image)
            let actionProxy = ActionProxy(onPress: onPress)
            self.actionProxy = actionProxy

            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = .clear
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            if let tintColor = Self.explicitTintColor {
                button.tintColor = tintColor
            }
            button.setImage(renderedImage, for: .normal)
            button.imageView?.contentMode = .center
            button.accessibilityLabel = resolvedAccessibilityLabel
            button.addTarget(actionProxy, action: #selector(ActionProxy.invoke), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.iconSize),
                button.heightAnchor.constraint(equalToConstant: Self.iconSize),
            ])
            self.button = button
        }

        public func setImage(_ image: UIImage?) {
            let renderedImage = Self.renderedImage(image)
            button.setImage(renderedImage, for: .normal)
        }

        private static var explicitTintColor: UIColor? {
            IOS_26_MODE_ENABLED ? .air.homeNavigationForeground : nil
        }

        private static let iconSize: CGFloat = 36

        private static func renderedImage(_ image: UIImage?) -> UIImage? {
            image?.withRenderingMode(.alwaysTemplate)
        }

        private final class ActionProxy: NSObject {
            private let onPress: () -> Void

            init(onPress: @escaping () -> Void) {
                self.onPress = onPress
            }

            @objc func invoke() {
                onPress()
            }
        }
    }

    public let barButtonItem: UIBarButtonItem?

    public init(items: [Item], spacing: CGFloat = 8) {
        switch items.count {
        case 0:
            barButtonItem = nil
        default:
            let stackView = UIStackView(arrangedSubviews: items.map(\.button))
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = spacing
            barButtonItem = UIBarButtonItem(customView: stackView)
        }
    }
}
