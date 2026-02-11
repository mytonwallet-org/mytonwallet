import SwiftUI

extension View {
    /// Conditionally applies a view modifier based on a Boolean condition.
    /// Generally, try not to use this.
    /// Where it is fully safe is `if #available(_, *)` conditions, because such condition can not be changed in runtime.
    /// When process is running, `if #available(_, *)` has always the same execution path.
    ///
    /// ## Cauton:
    /// 1. **Animation issues:** can disrupt animations if used not properly. If dynamically changed value used, view tree changes and
    /// SwiftUI can not rely on structural identity.
    /// This results in animations that fade between states, as if old view disappeared and new appeared, instead of smoothly interpolating the changes.
    /// 2. **State loss:** When a view, wrapped by `conditionally`, changes in runtime, the view hierarchy changes, leading to the reset of `@State`
    /// properties, which causes data loss.
    /// This issue is especially tricky because it might not be immediately obvious.
    ///
    /// [Link with more explanations](https://www.objc.io/blog/2021/08/24/conditional-view-modifiers/)
    ///
    /// # Example:
    /// ```swift
    /// .conditionally {
    ///   // ok, as iOS version can not be changed when process running
    ///   if #available(iOS 17.0, *) {
    ///     $0.someModifier()
    ///   } else {
    ///     $0.anotherModifier()
    ///   }
    /// }
    /// ```
    public func applyModifierConditionally<Content: View>(@ViewBuilder content: (Self) -> Content) -> some View {
        content(self)
    }
}
