import SwiftUI

extension View {
    /// Is used to conditionally hide or remove a view based on a boolean value.
    /// - Parameters:
    ///   - visible: if hidden is true and remove is false, we want to hide the view and keep the empty space with size of hidden view.
    ///   - remove: indicating whether the view should be removed from hierarchy view instead of just hidden.
    ///     In `false` case the view is not visible but the place for it is reserved.
    ///     In `true` case the view is removed from view hierarchy.
    public func isVisible(_ visible: Bool, remove: Bool) -> some View {
        modifier(IsHidden(hidden: !visible, remove: remove))
    }
}

/// Based on: https://www.devtechie.com/community/public/posts/231541-dynamically-hiding-view-in-swiftui
fileprivate struct IsHidden: ViewModifier {
    let hidden: Bool
    let remove: Bool

    func body(content: Content) -> some View {
        if hidden {
            if remove { // return nothing
            } else {
                content.hidden()
            }
        } else {
            content
        }
    }
}
