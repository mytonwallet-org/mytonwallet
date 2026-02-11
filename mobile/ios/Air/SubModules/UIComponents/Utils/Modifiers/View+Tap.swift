import SwiftUI

extension View {
    /// Adds a tappable interaction and tracks pressed state via a binding.
    /// The binding updates while pressed and can be used to animate child views.
    /// - Parameters:
    ///   - binding: Binding updated while the view is pressed (e.g., to animate children).
    ///   - action: Closure called when the tap completes inside the view.
    ///
    /// # Example:
    /// ```swift
    /// struct FolderView: View {
    ///   @State private var isPressed = false
    ///
    ///   var body: some View {
    ///     HStack {
    ///       Image(systemName: "star").scaleEffect(isPressed ? 1.2 : 1.0)
    ///       Image(systemName: "moon").scaleEffect(isPressed ? 1.2 : 1.0)
    ///     }
    ///     .onTap(isPressedBinding: $isPressed) { print("Tapped") }
    ///   }
    /// }
    /// ```
    public func onTap(isPressedBinding binding: Binding<Bool>,
                      action: @escaping @MainActor () -> Void) -> some View {
        modifier(PressedStateReportingButton(isPressedBinding: binding, action: action))
    }

    /// Adds a tappable interaction with a temporary highlight overlay while pressed.
    ///
    /// - Parameter action: Closure called when the tap completes inside the view.
    ///
    /// # Example:
    /// ```swift
    /// struct HighlightExample: View {
    ///   var body: some View {
    ///     Rectangle()
    ///       .onTapWithHighlight { print("Tapped with highlight") }
    ///   }
    /// }
    /// ```
    public func onTapWithHighlight(action: @escaping @MainActor () -> Void) -> some View {
        modifier(TapWithHighlightOverlay(action: action))
    }

    /// Uses `.buttonStyle(.plain)` to achieve the same behaviour as `scrollView.delaysContentTouches = false` in UIKit.
    /// PlainButtonStyle comes with 1) no delay 2) own highlight style, making it impossible to customize highlight.
    ///
    /// There are 2 further directions possible:
    /// 1. explore some other ways to achieve customizable highlight without delay in pure SwiftUI.
    /// 2. use UIKit.UIScrollView in SwiftUI with `.delaysContentTouches` = false.
    public func onTapWithHighlightInScroll(action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    Color.mint.opacity(0.65).frame(width: 40, height: 40).onTapWithHighlight {}

    ScrollView(.horizontal) {
        HStack(spacing: 4) {
            ForEach(0 ..< 8) { _ in
                Color.debugRandom().frame(width: 40, height: 40).onTapWithHighlight {}
            }
        }
    }.scrollIndicators(.never)
}
#endif

// MARK: Highlight modifiers with button tap semantics

fileprivate struct TapWithHighlightOverlay: ViewModifier {
    private let action: @MainActor () -> Void
    @State private var isPressed: Bool = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .highlightOverlay(isPressed)
            .modifier(PressedStateReportingButton(isPressedBinding: $isPressed, action: action))
    }
}

// MARK: - PressingState Reporting Tap

fileprivate struct PressedStateReportingButton: ViewModifier {
    private let action: @MainActor () -> Void
    @Binding private var isPressed: Bool

    init(isPressedBinding: Binding<Bool>,
         action: @escaping @MainActor () -> Void) {
        _isPressed = isPressedBinding
        self.action = action
    }

    func body(content: Content) -> some View {
        Button(action: action, label: { content })
            .buttonStyle(ButtonPressedStateReporter(isPressedBinding: $isPressed))
    }
}

/// A fake `ButtonStyle` that exposes the button’s pressed state via a binding without visual changes.
/// This allows you to track when a button is pressed and use the state to
/// animate or update child views without modifying the button’s appearance itself, e.g. highlight only nested icons while catching touches on the whole view.
fileprivate struct ButtonPressedStateReporter: ButtonStyle {
    @Binding private var isPressed: Bool

    init(isPressedBinding: Binding<Bool>) {
        _isPressed = isPressedBinding
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { newValue in
            isPressed = newValue
        }
    }
}

// MARK: - on FrameChange Modifier

extension View {
    public func onFrameChange(inCoordinateSpace coordinateSpace: CoordinateSpace,
                              emitChangesWhenOffscreen: Bool = false,
                              visibilityThreshold: Double = 0.1,
                              _ onChange: @escaping @MainActor (CGRect) -> Void) -> some View {
        modifier(FrameTrackerModifier(coordinateSpace: coordinateSpace,
                                      emitChangesWhenOffscreen: emitChangesWhenOffscreen,
                                      visibilityThreshold: visibilityThreshold,
                                      onFrameChange: onChange))
    }
}

fileprivate struct FrameTrackerModifier: ViewModifier {
    private let coordinateSpace: CoordinateSpace
    private let emitChangesWhenOffscreen: Bool
    private let visibilityThreshold: Double
    private let onFrameChange: (CGRect) -> Void

    /// Optimization to not call onFrameChange when view is out of scroll area.
    @State private var isVisible: Bool? = if #available(iOS 18.0, *) {
        nil
    } else {
        true // before iOS 18.0 onScrollVisibilityChange not available, so observe always
    }

    init(coordinateSpace: CoordinateSpace,
         emitChangesWhenOffscreen: Bool,
         visibilityThreshold: Double,
         onFrameChange: @escaping (CGRect) -> Void) {
        self.coordinateSpace = coordinateSpace
        self.emitChangesWhenOffscreen = emitChangesWhenOffscreen
        // clamp visibilityThreshold to the range 0…1 to prevent onScrollVisibilityChange incorrect behaviour
        self.visibilityThreshold = min(max(visibilityThreshold, 0), 1)
        self.onFrameChange = onFrameChange
    }

    func body(content: Content) -> some View {
        content.applyModifierConditionally {
            if #available(iOS 18.0, *) {
                $0.onScrollVisibilityChange(threshold: visibilityThreshold) { isVisible in
                    // This is called not only in scrollView, but also when view appears
                    self.isVisible = isVisible
                }
            } else {
                $0
            }
        }
        .onGeometryChange(for: CGRect.self, of: { proxy in
            proxy.frame(in: coordinateSpace)
        }, action: { frame in
            // isVisible == nil is for first emission, as `.onScrollVisibilityChange` is called
            // after `.onGeometryChange` when view appears.

            // One edge case is Scroll with Lazy view. When view is shown first time in lazy view, it appears
            // with isVisible == false in onScrollVisibilityChange closure according to threshold.
            // But as isVisible property == nil, onFrameChange called when view appears.
            if isVisible == true || isVisible == nil || emitChangesWhenOffscreen {
                onFrameChange(frame)
            }
        })
    }
}
