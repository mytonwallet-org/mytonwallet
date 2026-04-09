import UIKit

public enum ContextMenuCustomRowSizing: Sendable {
    case fixed(height: CGFloat)
    case automatic(minHeight: CGFloat = 44.0)
}

public enum ContextMenuCustomRowInteraction {
    case selectable(
        isEnabled: Bool = true,
        dismissesMenu: Bool = true,
        handler: (() -> Void)? = nil
    )
    case contentHandlesTouches
}

public struct ContextMenuCustomRowContext {
    private let dismissHandler: @MainActor () -> Void

    init(dismissHandler: @escaping @MainActor () -> Void) {
        self.dismissHandler = dismissHandler
    }

    @MainActor
    public func dismiss() {
        self.dismissHandler()
    }
}

public struct ContextMenuCustomRow {
    public typealias ViewProvider = @MainActor (ContextMenuCustomRowContext) -> UIView

    public var id: String
    public var preferredWidth: CGFloat?
    public var sizing: ContextMenuCustomRowSizing
    public var interaction: ContextMenuCustomRowInteraction
    public var makeContentView: ViewProvider

    public init(
        id: String = UUID().uuidString,
        preferredWidth: CGFloat? = nil,
        sizing: ContextMenuCustomRowSizing = .automatic(),
        interaction: ContextMenuCustomRowInteraction = .contentHandlesTouches,
        makeContentView: @escaping ViewProvider
    ) {
        self.id = id
        self.preferredWidth = preferredWidth
        self.sizing = sizing
        self.interaction = interaction
        self.makeContentView = makeContentView
    }
}

extension ContextMenuCustomRowInteraction {
    var isSelectable: Bool {
        switch self {
        case .selectable:
            return true
        case .contentHandlesTouches:
            return false
        }
    }

    var isEnabled: Bool {
        switch self {
        case let .selectable(isEnabled, _, _):
            return isEnabled
        case .contentHandlesTouches:
            return false
        }
    }

    var dismissesMenu: Bool {
        switch self {
        case let .selectable(_, dismissesMenu, _):
            return dismissesMenu
        case .contentHandlesTouches:
            return false
        }
    }

    var handler: (() -> Void)? {
        switch self {
        case let .selectable(_, _, handler):
            return handler
        case .contentHandlesTouches:
            return nil
        }
    }
}

extension ContextMenuCustomRowSizing {
    var fixedHeight: CGFloat? {
        switch self {
        case let .fixed(height):
            return height
        case .automatic:
            return nil
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case let .fixed(height):
            return height
        case let .automatic(minHeight):
            return minHeight
        }
    }
}
