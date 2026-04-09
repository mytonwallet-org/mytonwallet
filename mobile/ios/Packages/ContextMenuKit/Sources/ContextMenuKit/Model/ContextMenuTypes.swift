import UIKit

public struct ContextMenuConfiguration {
    public var rootPage: ContextMenuPage
    public var backdrop: ContextMenuBackdropStyle
    public var style: ContextMenuStyle

    public init(
        rootPage: ContextMenuPage,
        backdrop: ContextMenuBackdropStyle = .defaultBlurred(),
        style: ContextMenuStyle = .default
    ) {
        self.rootPage = rootPage
        self.backdrop = backdrop
        self.style = style
    }
}

public struct ContextMenuPage {
    public var id: String
    public var items: [ContextMenuItem]

    public init(id: String = UUID().uuidString, items: [ContextMenuItem]) {
        self.id = id
        self.items = items
    }
}

public enum ContextMenuItem {
    case action(ContextMenuAction)
    case back(ContextMenuBackAction)
    case submenu(ContextMenuSubmenu)
    case custom(ContextMenuCustomRow)
    case separator
}

public enum ContextMenuRole {
    case normal
    case destructive
}

public struct ContextMenuAction {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ContextMenuIcon?
    public var badgeText: String?
    public var role: ContextMenuRole
    public var isEnabled: Bool
    public var dismissesMenu: Bool
    public var handler: (() -> Void)?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        icon: ContextMenuIcon? = nil,
        badgeText: String? = nil,
        role: ContextMenuRole = .normal,
        isEnabled: Bool = true,
        dismissesMenu: Bool = true,
        handler: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badgeText = badgeText
        self.role = role
        self.isEnabled = isEnabled
        self.dismissesMenu = dismissesMenu
        self.handler = handler
    }
}

public struct ContextMenuBackAction {
    public var id: String
    public var title: String
    public var icon: ContextMenuIcon?
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        icon: ContextMenuIcon? = .system("chevron.left"),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
    }
}

public struct ContextMenuSubmenu {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ContextMenuIcon?
    public var badgeText: String?
    public var isEnabled: Bool
    public var makePage: () -> ContextMenuPage

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        icon: ContextMenuIcon? = nil,
        badgeText: String? = nil,
        isEnabled: Bool = true,
        makePage: @escaping () -> ContextMenuPage
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badgeText = badgeText
        self.isEnabled = isEnabled
        self.makePage = makePage
    }
}

public enum ContextMenuBackdropStyle {
    case none
    case dimmed(alpha: CGFloat)
    case blurred(style: UIBlurEffect.Style, dimAlpha: CGFloat)

    public static func defaultBlurred(
        style: UIBlurEffect.Style = .systemUltraThinMaterial,
        dimAlpha: CGFloat = 0.14
    ) -> ContextMenuBackdropStyle {
        .blurred(style: style, dimAlpha: dimAlpha)
    }
}

public enum ContextMenuVerticalPlacementBehavior: Sendable {
    case screenBalanced
    case sourceAttached
}

public struct ContextMenuStyle: Sendable {
    public var minWidth: CGFloat
    public var maxWidth: CGFloat
    public var maximumHeightRatio: CGFloat
    public var verticalPlacementBehavior: ContextMenuVerticalPlacementBehavior
    public var sourceSpacing: CGFloat
    public var panelCornerRadius: CGFloat
    public var panelInset: CGFloat
    public var listVerticalPadding: CGFloat
    public var highlightHorizontalInset: CGFloat
    public var rowSideInset: CGFloat
    public var rowVerticalInset: CGFloat
    public var iconSideInset: CGFloat
    public var standardIconWidth: CGFloat
    public var iconSpacing: CGFloat
    public var separatorHeight: CGFloat
    public var containerSpacing: CGFloat
    public var screenInsets: UIEdgeInsets

    public init(
        minWidth: CGFloat = 220.0,
        maxWidth: CGFloat = 280.0,
        maximumHeightRatio: CGFloat = 0.62,
        verticalPlacementBehavior: ContextMenuVerticalPlacementBehavior = .sourceAttached,
        sourceSpacing: CGFloat = 8.0,
        panelCornerRadius: CGFloat = 30.0,
        panelInset: CGFloat = 32.0,
        listVerticalPadding: CGFloat = 10.0,
        highlightHorizontalInset: CGFloat = 10.0,
        rowSideInset: CGFloat = 18.0,
        rowVerticalInset: CGFloat = 11.0,
        iconSideInset: CGFloat = 20.0,
        standardIconWidth: CGFloat = 32.0,
        iconSpacing: CGFloat = 8.0,
        separatorHeight: CGFloat = 20.0,
        containerSpacing: CGFloat = 7.0,
        screenInsets: UIEdgeInsets = .init(top: 16.0, left: 16.0, bottom: 0.0, right: 16.0)
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.maximumHeightRatio = maximumHeightRatio
        self.verticalPlacementBehavior = verticalPlacementBehavior
        self.sourceSpacing = sourceSpacing
        self.panelCornerRadius = panelCornerRadius
        self.panelInset = panelInset
        self.listVerticalPadding = listVerticalPadding
        self.highlightHorizontalInset = highlightHorizontalInset
        self.rowSideInset = rowSideInset
        self.rowVerticalInset = rowVerticalInset
        self.iconSideInset = iconSideInset
        self.standardIconWidth = standardIconWidth
        self.iconSpacing = iconSpacing
        self.separatorHeight = separatorHeight
        self.containerSpacing = containerSpacing
        self.screenInsets = screenInsets
    }

    public static let `default` = ContextMenuStyle()
}
