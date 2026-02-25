import UIKit

extension UIView {
    /// Adds a subview to the current view and pins it to the parent’s edges with optional padding defined by `UIEdgeInsets`.
    public func addStretchedToBounds(subview: UIView, insets: UIEdgeInsets = .zero) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        
        let constraints: [NSLayoutConstraint] = [
            subview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            subview.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            trailingAnchor.constraint(equalTo: subview.trailingAnchor, constant: insets.right),
            bottomAnchor.constraint(equalTo: subview.bottomAnchor, constant: insets.bottom),
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
    public func addStretchedToSafeArea(subview: UIView,
                                       leading: (UIView) -> NSLayoutXAxisAnchor = \.safeAreaLayoutGuide.leadingAnchor,
                                       trailing: (UIView) -> NSLayoutXAxisAnchor = \.safeAreaLayoutGuide.trailingAnchor,
                                       top: (UIView) -> NSLayoutYAxisAnchor = \.safeAreaLayoutGuide.topAnchor,
                                       bottom: (UIView) -> NSLayoutYAxisAnchor = \.safeAreaLayoutGuide.bottomAnchor,
                                       insets: UIEdgeInsets = .zero) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        
        let constraints: [NSLayoutConstraint] = [
            subview.leadingAnchor.constraint(equalTo: leading(self), constant: insets.left),
            subview.topAnchor.constraint(equalTo: top(self), constant: insets.top),
            trailing(self).constraint(equalTo: subview.trailingAnchor, constant: insets.right),
            bottom(self).constraint(equalTo: subview.bottomAnchor, constant: insets.bottom),
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
}

extension UIView {
    /// inversion of .isHidden
    public var isVisible: Bool {
        get { !isHidden }
        set { isHidden = !newValue }
    }
}
