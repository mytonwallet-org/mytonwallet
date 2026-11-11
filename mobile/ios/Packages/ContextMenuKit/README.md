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
- `ContextMenuSourceRelocation`
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

Set `ContextMenuConfiguration.popoverDisablesInteractiveDismissal` to `true` to
keep the popover anchored without replacing this transition. The host enables
`isModalInPresentation` and adds a transparent outside control beneath the popup
in its presentation container. Only that control is registered in
`passthroughViews`, allowing outside taps to invoke native dismissal while
shielding the presenting screen. Content scrolling, row actions and VoiceOver
Escape remain available. Cleanup removes the control and restores the previous
passthrough views. This option
defaults to `false` and does not affect overlay or sheet presentations.

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

An action's `animatedIcon` replaces its icon image with a view conforming to `ContextMenuAnimatedIconView`, made when the row is. The image still sizes and places the icon, and the view gets `playHighlightAnimation()` each time its row becomes highlighted, whether by a tap, a finger sliding across the menu or one dragged on from the source. A provider that returns nil keeps the image:

```swift
ContextMenuAction(
    title: "Wallet",
    icon: .image(walletImage),
    handler: openWallet,
    animatedIcon: { reducesMotion ? nil : WalletIconAnimationView() }
)
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

An overlay menu can show an accessory over its source's top edge, such as a row of reactions. The accessory is placed by the offset of its top trailing corner from the source's top trailing corner and kept inside the screen; the panel attaches clear of the source and the accessory whatever `verticalPlacementBehavior` says, and when neither side has room, as for a source taller than the screen, it overlaps the source at the bottom. The menu panel's material fills `backgroundCapsules`, merging the ones that overlap into one shape, with the panel's tint unless `glassTint` sets another and, before native glass, the panel's shadow; the content view handles its own taps, and taps inside the accessory never dismiss the menu. Right-to-left layouts mirror the placement and the capsules:

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

A thought bubble keeps its `tail` capsules at the source's corner while the rest slides inward to stay `screenInset` from the safe area's sides; a tail that would then come nearer the sides than its `edgeSpacing`, or leave the capsule it hangs from, goes with the rest instead. Its `.thoughtBubble` motion pops the tail in from its smallest capsule, grows the rest out of a circle at its trailing end and shrinks it back toward the tail as the menu closes, fading instead with Reduce Motion. A content view that conforms to `ContextMenuAccessoryAnimating` gets the motion's timing to show its parts as the growing capsule reaches them, and `context.dismiss(completion:)` reports when the menu is gone. `context.getSourceFrameOnScreen(_:)` tells where a part of the source shows on screen at the moment, on its replica wherever the replica moves, for something to fly to it as the menu closes. With native glass, the capsule that holds the content is drawn over the tail, which is its background. An accessory's `shadow` fades out while a finger is on interactive glass, which swells and stretches toward the finger away from where the shadow is cut out for it, and comes back once the glass settles.

A portal-backed overlay menu can move its source into view, as Telegram moves a message for its menu. With `sourceRelocation`, the portal replica stands in for the hidden source and, together with the accessory and the panel hanging below it, fits between the safe area's edges inset by `topInset` and `bottomInset`, moving no further than it must on Telegram's spring. A replica and panel taller than that scroll, opening at the panel, while the accessory stays in reach: it rides over the replica but never goes above the top limit, so the replica scrolls under it. `contentAreaInWindow` clips the replica to where the source shows under the screen's bars as the menu opens and closes. Until the menu's backdrop covers the bars, the bars keep showing the parts of the source under them: the source itself when its replica stays on it, or a copy of those parts that moves with the replica when the replica moves, so the bars never show the source where the replica has left it, and which leaves the content area clear even where the source draws beyond its bounds. Like the replica, the copy is a portal of the source, so it shows the source as the replica does all the way, the press's squeeze letting go included:

```swift
ContextMenuConfiguration(
    rootPage: page,
    sourceRelocation: ContextMenuSourceRelocation(contentAreaInWindow: chatAreaBetweenHeaderAndComposer)
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
