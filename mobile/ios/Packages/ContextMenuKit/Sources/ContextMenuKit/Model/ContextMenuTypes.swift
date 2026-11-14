import UIKit

public struct ContextMenuConfiguration {
    public var rootPage: ContextMenuPage
    public var backdrop: ContextMenuBackdropStyle
    public var backdropTintColor: UIColor?
    /// Leave the source in place without compositing a translucent replica over it.
    public var preservesSourceAppearance: Bool
    public var backdropBlurPolicy: ContextMenuBackdropBlurPolicy
    public var popoverVerticalAlignment: ContextMenuPopoverVerticalAlignment
    /// Overrides the menu's appearance while preserving the source view's appearance.
    public var userInterfaceStyle: UIUserInterfaceStyle?
    /// Uses the visible source width for controls whose intrinsic content extends beyond their viewport.
    public var popoverUsesSourceViewBounds: Bool
    /// Disables native interactive popover dismissal; outside taps, row actions, and accessibility escape still dismiss.
    public var popoverDisablesInteractiveDismissal: Bool
    /// Adds adaptive system material behind content presented over visually busy surfaces.
    public var popoverBackgroundMaterial: UIBlurEffect.Style?
    public var style: ContextMenuStyle
    /// A view over the source's top edge, which only the overlay presentation shows. With one, the panel attaches
    /// clear of the source and the accessory, so `style.verticalPlacementBehavior` does not apply.
    public var accessory: ContextMenuAccessory?
    /// Moves the source's portal replica into view, as Telegram moves a message for its menu. Applies to the overlay
    /// presentation of a source portal.
    public var sourceRelocation: ContextMenuSourceRelocation?
    /// An optional navigation host for handing the sheet over to another flow.
    public var sheetNavigationControllerProvider: (@MainActor (UIViewController) -> UINavigationController)?

    public init(
        rootPage: ContextMenuPage,
        backdrop: ContextMenuBackdropStyle = .defaultBlurred(),
        backdropTintColor: UIColor? = nil,
        preservesSourceAppearance: Bool = false,
        backdropBlurPolicy: ContextMenuBackdropBlurPolicy = .enabled,
        popoverVerticalAlignment: ContextMenuPopoverVerticalAlignment = .automatic,
        userInterfaceStyle: UIUserInterfaceStyle? = nil,
        popoverUsesSourceViewBounds: Bool = false,
        popoverDisablesInteractiveDismissal: Bool = false,
        popoverBackgroundMaterial: UIBlurEffect.Style? = nil,
        style: ContextMenuStyle = .default,
        accessory: ContextMenuAccessory? = nil,
        sourceRelocation: ContextMenuSourceRelocation? = nil,
        sheetNavigationControllerProvider: (@MainActor (UIViewController) -> UINavigationController)? = nil
    ) {
        self.rootPage = rootPage
        self.backdrop = backdrop
        self.backdropTintColor = backdropTintColor
        self.preservesSourceAppearance = preservesSourceAppearance
        self.backdropBlurPolicy = backdropBlurPolicy
        self.popoverVerticalAlignment = popoverVerticalAlignment
        self.userInterfaceStyle = userInterfaceStyle
        self.popoverUsesSourceViewBounds = popoverUsesSourceViewBounds
        self.popoverDisablesInteractiveDismissal = popoverDisablesInteractiveDismissal
        self.popoverBackgroundMaterial = popoverBackgroundMaterial
        self.style = style
        self.accessory = accessory
        self.sourceRelocation = sourceRelocation
        self.sheetNavigationControllerProvider = sheetNavigationControllerProvider
    }

    func resolved(for sourceView: UIView) -> ContextMenuConfiguration {
        guard backdropBlurPolicy == .disabledInRegularWidth,
              sourceView.contextMenuUsesRegularWidthLayout else {
            return self
        }

        var configuration = self
        switch backdrop {
        case let .blurred(_, dimAlpha), let .untintedBlur(_, dimAlpha):
            configuration.backdrop = .dimmed(alpha: dimAlpha)
        case .none, .dimmed:
            break
        }
        return configuration
    }
}

public struct ContextMenuPage {
    public var id: String
    public var items: [ContextMenuItem]
    public var layout: ContextMenuPageLayout
    /// Holding an action row still lifts it, and dragging it reorders the page's actions.
    /// Called with the row's old and new index on each step, while the finger is still down.
    /// Only list pages made entirely of actions support it
    public var onReorder: ((_ sourceIndex: Int, _ destinationIndex: Int) -> Void)?

    public init(
        id: String = UUID().uuidString,
        items: [ContextMenuItem],
        layout: ContextMenuPageLayout = .list,
        onReorder: ((_ sourceIndex: Int, _ destinationIndex: Int) -> Void)? = nil
    ) {
        self.id = id
        self.items = items
        self.layout = layout
        self.onReorder = onReorder
    }

    @MainActor
    public func measuredSize(
        maxWidth: CGFloat,
        style: ContextMenuStyle,
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> CGSize {
        let pageView = ContextMenuPageView(
            page: self,
            style: style,
            sourceUserInterfaceLayoutDirection: layoutDirection,
            customRowContext: ContextMenuCustomRowContext(dismissHandler: {})
        )
        return pageView.preferredSize(constrainedTo: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
    }
}

public enum ContextMenuPageLayout: Sendable {
    case list
    case grid(ContextMenuGridLayout)
}

public struct ContextMenuGridLayout: Sendable {
    public var columns: Int
    public var contentInsets: UIEdgeInsets
    public var highlightInsets: UIEdgeInsets
    public var highlightCornerRadius: CGFloat

    public init(
        columns: Int,
        contentInsets: UIEdgeInsets = .zero,
        highlightInsets: UIEdgeInsets = .zero,
        highlightCornerRadius: CGFloat = 20.0
    ) {
        self.columns = max(1, columns)
        self.contentInsets = contentInsets
        self.highlightInsets = highlightInsets
        self.highlightCornerRadius = highlightCornerRadius
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
    public var accessibilityIdentifier: String?
    public var handler: (() -> Void)?
    /// Replaces the icon image, which still sizes and places it
    public var animatedIcon: ContextMenuAnimatedIconProvider?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        icon: ContextMenuIcon? = nil,
        badgeText: String? = nil,
        role: ContextMenuRole = .normal,
        isEnabled: Bool = true,
        dismissesMenu: Bool = true,
        accessibilityIdentifier: String? = nil,
        handler: (() -> Void)? = nil,
        // Follows `handler`, so that a trailing closure binds to `handler`
        animatedIcon: ContextMenuAnimatedIconProvider? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badgeText = badgeText
        self.role = role
        self.isEnabled = isEnabled
        self.dismissesMenu = dismissesMenu
        self.accessibilityIdentifier = accessibilityIdentifier
        self.handler = handler
        self.animatedIcon = animatedIcon
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
        icon: ContextMenuIcon? = .system("chevron.backward"),
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
    /// Gaussian blur without the system material's theme-dependent tint or saturation.
    case untintedBlur(radius: CGFloat, dimAlpha: CGFloat)

    public static func defaultBlurred(
        style: UIBlurEffect.Style = .systemUltraThinMaterial,
        dimAlpha: CGFloat = 0.14
    ) -> ContextMenuBackdropStyle {
        .blurred(style: style, dimAlpha: dimAlpha)
    }
}

public enum ContextMenuBackdropBlurPolicy: Equatable, Sendable {
    case enabled
    case disabledInRegularWidth
}

private extension UIView {
    var contextMenuUsesRegularWidthLayout: Bool {
        switch traitCollection.horizontalSizeClass {
        case .regular:
            return true
        case .compact:
            return false
        case .unspecified:
            return window?.traitCollection.horizontalSizeClass == .regular
        @unknown default:
            return false
        }
    }
}

/// Telegram's placement of a message under its menu. The source's replica and the panel hanging below it fit between
/// the safe area's edges inset by `topInset` and `bottomInset`, moving the replica no further than they must, and scroll
/// when they are taller than that, starting at the panel. The source itself hides while its replica shows.
///
/// The panel always hangs below the source and its accessory, so `style.verticalPlacementBehavior` does not apply.
public struct ContextMenuSourceRelocation: Sendable {
    public var topInset: CGFloat
    public var bottomInset: CGFloat
    /// The window rect where the source is visible under the screen's own bars, such as a chat between its navigation
    /// bar and input panel. The replica is clipped to it as the menu opens and closes, so a source partly under a bar
    /// slides out from behind it and back.
    public var contentAreaInWindow: CGRect?

    public init(topInset: CGFloat = 8.0, bottomInset: CGFloat = 10.0, contentAreaInWindow: CGRect? = nil) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.contentAreaInWindow = contentAreaInWindow
    }
}

public enum ContextMenuVerticalPlacementBehavior: Sendable {
    case screenBalanced
    case sourceAttached
    case screenBottom
}

/// Where a panel sits horizontally relative to its source
public enum ContextMenuHorizontalAlignment: Equatable, Sendable {
    /// Centred on the source
    case center
    /// The panel's leading edge on the source's, as Telegram aligns a message's menu with an incoming bubble
    case leading
    /// The panel's trailing edge on the source's, as for an outgoing bubble
    case trailing
}

/// Tint presets for native menu glass on iOS 26 and later.
public enum ContextMenuGlassTint: Equatable, Sendable {
    /// Stronger separation from underlying content: 60% white in light mode, 20% in dark mode.
    case strong
    /// The original tint: 10% white in light mode, 2.5% in dark mode.
    case subtle
}

public struct ContextMenuStyle: Sendable {
    public var minWidth: CGFloat
    public var maxWidth: CGFloat
    public var maximumHeightRatio: CGFloat
    public var verticalPlacementBehavior: ContextMenuVerticalPlacementBehavior
    public var sourceSpacing: CGFloat
    public var animationSourceSpacing: CGFloat?
    public var glassTint: ContextMenuGlassTint
    public var panelCornerRadius: CGFloat
    public var panelInset: CGFloat
    public var listVerticalPadding: CGFloat
    public var highlightHorizontalInset: CGFloat
    public var rowSideInset: CGFloat
    public var rowVerticalInset: CGFloat
    public var subtitleNumberOfLines: Int
    public var iconSideInset: CGFloat
    public var standardIconWidth: CGFloat
    public var iconSpacing: CGFloat
    public var separatorHeight: CGFloat
    public var containerSpacing: CGFloat
    public var screenInsets: UIEdgeInsets
    public var horizontalAlignment: ContextMenuHorizontalAlignment
    /// Rows without an icon start their text where the separators start, rather than at `rowSideInset`
    public var alignsPlainTitlesWithSeparators = false

    /// Where a separator's line starts and ends, from the panel's sides
    var separatorSideInset: CGFloat {
        rowSideInset + 4.0
    }

    /// Where the text of a row without an icon starts, from the panel's leading side
    var plainTitleSideInset: CGFloat {
        alignsPlainTitlesWithSeparators ? separatorSideInset : rowSideInset
    }

    public init(
        minWidth: CGFloat = 220.0,
        maxWidth: CGFloat = 280.0,
        maximumHeightRatio: CGFloat = 0.62,
        verticalPlacementBehavior: ContextMenuVerticalPlacementBehavior = .sourceAttached,
        sourceSpacing: CGFloat = 8.0,
        animationSourceSpacing: CGFloat? = nil,
        glassTint: ContextMenuGlassTint = .subtle,
        panelCornerRadius: CGFloat = 30.0,
        panelInset: CGFloat = 32.0,
        listVerticalPadding: CGFloat = 10.0,
        highlightHorizontalInset: CGFloat = 10.0,
        rowSideInset: CGFloat = 18.0,
        rowVerticalInset: CGFloat = 11.0,
        subtitleNumberOfLines: Int = 1,
        iconSideInset: CGFloat = 20.0,
        standardIconWidth: CGFloat = 32.0,
        iconSpacing: CGFloat = 8.0,
        separatorHeight: CGFloat = 20.0,
        containerSpacing: CGFloat = 7.0,
        screenInsets: UIEdgeInsets = .init(top: 16.0, left: 16.0, bottom: 0.0, right: 16.0),
        horizontalAlignment: ContextMenuHorizontalAlignment = .center
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.maximumHeightRatio = maximumHeightRatio
        self.verticalPlacementBehavior = verticalPlacementBehavior
        self.sourceSpacing = sourceSpacing
        self.animationSourceSpacing = animationSourceSpacing
        self.glassTint = glassTint
        self.panelCornerRadius = panelCornerRadius
        self.panelInset = panelInset
        self.listVerticalPadding = listVerticalPadding
        self.highlightHorizontalInset = highlightHorizontalInset
        self.rowSideInset = rowSideInset
        self.rowVerticalInset = rowVerticalInset
        self.subtitleNumberOfLines = subtitleNumberOfLines
        self.iconSideInset = iconSideInset
        self.standardIconWidth = standardIconWidth
        self.iconSpacing = iconSpacing
        self.separatorHeight = separatorHeight
        self.containerSpacing = containerSpacing
        self.screenInsets = screenInsets
        self.horizontalAlignment = horizontalAlignment
    }

    public static let `default` = ContextMenuStyle()
}
