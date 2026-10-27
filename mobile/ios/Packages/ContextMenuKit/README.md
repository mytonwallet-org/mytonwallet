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
- optional iOS 26 source-replacement zoom popovers

## Requirements

- iOS 16.0+
- Xcode 16+ recommended

## Package Layout

- `Package.swift`: Swift package manifest
- `Sources/ContextMenuKit`: library sources
- `Tests/ContextMenuKitTests`: unit tests, run with `xcodebuild test -scheme ContextMenuKit` and an iOS Simulator destination
- `Examples/ContextMenuDemoApp`: checked-in example app with a local package dependency

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
- `ContextMenuAccessory`
- `ContextMenuAccessoryContext`
- `ContextMenuIcon`
- `ContextMenuIconRenderingMode`
- `ContextMenuBackdropStyle`
- `ContextMenuVerticalPlacementBehavior`
- `ContextMenuStyle`
- `ContextMenuPresentationMode`
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

On iOS 26 and later, a menu can use UIKit's arrowless source-replacement
popover. Earlier iOS versions resolve this mode to the standard overlay:

```swift
let interaction = ContextMenuInteraction(
    triggers: [.tap, .longPress],
    presentationMode: .zoomPopover,
    activationViewProvider: { _ in visibleSourceView }
) { _ in
    configuration
}

interaction.attach(to: hitView)
```

The visible transition source can be any `UIView`; it does not need to use
Liquid Glass. Internally, the iOS 26 host exposes that view through a retained
`UIBarButtonItem(customView:)` source item, allowing `UIPopoverPresentationController`
to own the native replace/restore lifecycle. It does not install a second zoom
transition. Backdrop and source-portal rendering remain specific to the overlay
fallback because UIKit owns the popover's chrome and presentation.

Set `ContextMenuConfiguration.popoverVerticalAlignment` to `.sourceTop` to align
the popover's top edge with its source when the menu fits below it. UIKit keeps
its automatic placement when there is insufficient space. The default is
`.automatic`; this setting does not affect overlay or sheet presentations.

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
            interaction: .selectable(
                allowsContentInteraction: true,
                handler: onCopy
            )
        ) { context in
            AddressRowView(
                onOpenExplorer: {
                    openExplorer()
                    context.dismiss()
                }
            )
        }
    )
])
```

Use `allowsContentInteraction` when the row has a default selection action but also contains an independent `UIControl`, such as an explorer accessory button.
Use the `.submenu` interaction instead when a custom row should navigate to another `ContextMenuPage` while preserving independent controls.

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

An overlay menu can show an accessory over its source's top edge, such as a row of reactions. The accessory is placed by the offset of its top trailing corner from the source's top trailing corner and kept inside the screen; the panel attaches clear of the source and the accessory whatever `verticalPlacementBehavior` says, and when neither side has room, as for a source taller than the screen, it overlaps the source at the bottom. The menu panel's material fills `backgroundCapsules`, merging the ones that overlap into one shape, the content view handles its own taps, and taps inside the accessory never dismiss the menu. Right-to-left layouts mirror the placement and the capsules:

```swift
ContextMenuConfiguration(
    rootPage: page,
    accessory: ContextMenuAccessory(
        size: CGSize(width: 104.0, height: 52.0),
        topTrailingOffset: CGVector(dx: 16.0, dy: -40.0),
        backgroundCapsules: [CGRect(x: 0.0, y: 0.0, width: 104.0, height: 52.0)]
    ) { context in
        ReactionsView(onSelect: { reaction in
            react(reaction)
            context.dismiss()
        })
    }
)
```

For source-attached menus, `ContextMenuStyle` now defaults to:

- `verticalPlacementBehavior = .sourceAttached`
- `screenInsets.bottom = 0`
- animation anchor spacing follows `sourceSpacing` by default

If you need the previous Telegram-inspired screen-balanced placement, override:

```swift
var style = ContextMenuStyle()
style.verticalPlacementBehavior = .screenBalanced
```

If a menu overlaps its source using a negative `sourceSpacing`, but you still want the animation to originate from a positive offset relative to the source, set `animationSourceSpacing` explicitly.

Native menu glass on iOS 26 and later defaults to `glassTint: .subtle` (10% white in light mode, 2.5% in dark mode). For stronger separation from underlying content in a specific menu, choose `.strong` (60% white in light mode, 20% in dark mode):

```swift
let style = ContextMenuStyle(glassTint: .strong)
// Or update an existing configuration:
configuration.style.glassTint = .strong
```

The chosen tint also applies to submenu pages. Earlier iOS versions keep their existing material appearance.

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
- Telegram-style fully custom/dynamic content pages are not supported yet and remain future work.
