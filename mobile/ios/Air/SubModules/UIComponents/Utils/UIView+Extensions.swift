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
}
