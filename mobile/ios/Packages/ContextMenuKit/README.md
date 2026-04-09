# ContextMenuKit

`ContextMenuKit` is an extracted iOS context menu component based on Telegram's custom menu implementation.

It is packaged as a standalone Swift package with:

- Telegram-style list menus
- tap and long-press presentation
- hold-and-drag item selection
- scrollable content
- submenu navigation
- arbitrary custom row content inside list pages
- iOS 26 glass presentation
- iOS 16+ fallback material background
- UIKit and SwiftUI source attachment APIs
- optional source cloning via portal views

## Requirements

- iOS 16.0+
- Xcode 16+ recommended

## Package Layout

- `Package.swift`: Swift package manifest
- `Sources/ContextMenuKit`: library sources
- `Examples/ContextMenuDemoApp`: checked-in example app with a local package dependency
- `TECHNICAL_OVERVIEW.md`: architecture notes and Telegram parity references
- `REFACTOR_PLAN.md`: refactor history and package-prep checklist

## Public API

The main public entry points are:

- `ContextMenuConfiguration`
- `ContextMenuPage`
- `ContextMenuItem`
- `ContextMenuAction`
- `ContextMenuBackAction`
- `ContextMenuSubmenu`
- `ContextMenuCustomRow`
- `ContextMenuCustomRowSizing`
- `ContextMenuCustomRowInteraction`
- `ContextMenuCustomRowContext`
- `ContextMenuIcon`
- `ContextMenuIconRenderingMode`
- `ContextMenuBackdropStyle`
- `ContextMenuVerticalPlacementBehavior`
- `ContextMenuStyle`
- `ContextMenuInteraction`
- `ContextMenuInteractionTriggers`
- `ContextMenuSourcePortal`
- SwiftUI `contextMenuSource(...)`

## Using The Package

Add the package to your project and import `ContextMenuKit`.

UIKit sources use `ContextMenuInteraction`:

```swift
let interaction = ContextMenuInteraction(triggers: [.tap, .longPress]) { sourceView in
    ContextMenuConfiguration(
        rootPage: ContextMenuPage(items: [
            .action(ContextMenuAction(title: "Reply")),
            .action(ContextMenuAction(title: "Delete", role: .destructive))
        ])
    )
}

interaction.attach(to: button)
```

SwiftUI sources use the modifier:

```swift
MySourceView()
    .contextMenuSource(triggers: [.tap, .longPress]) {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(ContextMenuAction(title: "Reply"))
            ])
        )
}
```

Custom rows can host arbitrary UIKit content or use the SwiftUI convenience:

```swift
ContextMenuPage(items: [
    .custom(
        .swiftUI(
            sizing: .fixed(height: 58.0),
            interaction: .selectable(handler: onSelectUSD)
        ) { _ in
            CurrencyRow(title: "USD", subtitle: "$14,480.12", isSelected: true)
        }
    ),
    .custom(
        ContextMenuCustomRow(
            sizing: .fixed(height: 60.0),
            interaction: .contentHandlesTouches
        ) { context in
            AddressRowView(
                onCopy: {
                    copyAddress()
                    context.dismiss()
                },
                onOpenExplorer: {
                    openExplorer()
                    context.dismiss()
                }
            )
        }
    )
])
```

For portal-backed source cloning, provide `ContextMenuSourcePortal`:

```swift
.contextMenuSource(
    triggers: [.tap, .longPress],
    sourcePortal: ContextMenuSourcePortal(
        sourceViewProvider: { containerView },
        mask: .roundedAttachmentRect(cornerRadius: 22.0, cornerCurve: .continuous)
    )
) {
    configuration
}
```

By default, portal-backed menus keep the backdrop continuous and render only the lifted portal clone. If you also want a matching hole cut out of the blur/dimming behind it, opt in with `showsBackdropCutout: true`.

If the visible source shape is not just a simple rounded rect, `mask` also supports `.customAttachmentPath { rect in ... }` so the portal clone and backdrop cutout can use the exact same shape.

For source-attached menus, `ContextMenuStyle` now defaults to:

- `verticalPlacementBehavior = .sourceAttached`
- `screenInsets.bottom = 0`

If you need the previous Telegram-inspired screen-balanced placement, override:

```swift
var style = ContextMenuStyle()
style.verticalPlacementBehavior = .screenBalanced
```

For aligned rows with a leading placeholder or a custom bundle-backed image, use `icon`:

```swift
ContextMenuAction(
    title: currencyName,
    icon: isSelected
        ? .custom("BaseCurrencyCheckmark", bundle: AirBundle, renderingMode: .original)
        : .placeholder,
    handler: onSelect
)
```

For submenu pages that need an explicit top back row, use `.back(...)`:

```swift
ContextMenuPage(items: [
    .back(ContextMenuBackAction(title: "Back")),
    .separator,
    .action(ContextMenuAction(title: "Saved Messages", icon: .system("bookmark"), handler: onSavedMessages))
])
```

## Example App

Open:

- `Examples/ContextMenuDemoApp/ContextMenuDemoApp.xcodeproj`

The example project is checked in directly and does not depend on `xcodegen` or any other project-generation tool.

## Notes

- `ContextMenuKit` is intentionally narrower than Telegram's full menu framework.
- The current public model supports standard list rows, submenus, separators, and custom rows inside list pages.
- Telegram-style fully custom/dynamic content pages are still documented in `TECHNICAL_OVERVIEW.md` as future work.
