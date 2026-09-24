import Foundation

public struct SharedBottomToolbarAction: Equatable, Identifiable, Sendable {
    public enum Style: Equatable, Sendable {
        case accent
        case positive
        case negative
    }

    public let id: String
    public var title: String
    public var accessibilityLabel: String
    public var style: Style

    public init(
        id: String,
        title: String,
        accessibilityLabel: String? = nil,
        style: Style = .accent
    ) {
        self.id = id
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.style = style
    }
}

/// A screen can donate actions to a navigation container's shared bottom toolbar.
///
/// The provider owns action behavior while the container owns presentation and
/// transitions. This keeps feature-specific routing out of the toolbar view.
@MainActor
public protocol SharedBottomToolbarContentProviding: AnyObject {
    var isSharedBottomToolbarEnabled: Bool { get }
    var sharedBottomToolbarActions: [SharedBottomToolbarAction] { get }
    /// Notify the host when actions or toolbar availability change.
    var onSharedBottomToolbarActionsChange: (() -> Void)? { get set }

    func setSharedBottomToolbarHosted(_ isHosted: Bool)
    func performSharedBottomToolbarAction(id: String)
}

extension SharedBottomToolbarContentProviding {
    public var isSharedBottomToolbarEnabled: Bool { true }
}
