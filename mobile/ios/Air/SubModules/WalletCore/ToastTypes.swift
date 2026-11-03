import Foundation

public enum ToastStyle: Equatable {
    case standard, large
    /// Telegram's undo overlay: 12 pt from the screen's edges, 14 pt text on up to two lines
    case overlay
}

public enum ToastIcon: Equatable {
    case animatedCopy
    case symbolImage(String)
    case networkImage(URL)
}

public enum ToastTransition {
    case fadeIn
    case floatUp
    /// Telegram's undo overlay: fades in as it grows from 96% on a spring, and fades out as it shrinks back
    case scale
}

public struct ToastConfig {
    public var style: ToastStyle
    public var icon: ToastIcon?
    public var message: String
    public var duration: Double
    public var transition: ToastTransition
    public var actionTitle: String?
    public var action: (() -> ())?

    public init(style: ToastStyle? = nil, icon: ToastIcon? = nil, message: String, duration: Double? = nil,
                transition: ToastTransition? = nil, actionTitle: String? = nil, action: (() -> ())? = nil) {
        self.style = style ?? .standard
        self.icon = icon
        self.message = message
        self.duration = duration ?? 3.0
        self.transition = transition ?? .fadeIn
        self.actionTitle = actionTitle
        self.action = action
    }
}
