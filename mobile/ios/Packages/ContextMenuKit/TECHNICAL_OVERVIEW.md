# ContextMenuKit Technical Overview

## Purpose

`ContextMenuKit` is an isolated extraction of the Telegram chat context menu interaction model, rebuilt without Telegram app dependencies.

The current goal is narrow and deliberate:

- match Telegram’s menu UI and interaction quality for list-based menus
- support tap and long-press opening
- support hold-and-drag selection
- support optional blurred backdrop
- support scrollable content
- support submenu navigation
- support arbitrary custom rows inside list pages
- preserve iOS 26 glass behavior while offering a simpler iOS 16+ fallback material path
- keep the implementation reusable and library-friendly

The current implementation is **not** a full port of Telegram’s context menu framework. It is a focused UIKit recreation of the menu stack that matters for the target use case.

## Current Scope

The extracted implementation currently covers:

- a reusable menu model
- a presentation/overlay controller
- a glass menu panel with iOS 26 material effects
- list row layout and separators
- custom row layout with fixed or automatic sizing
- highlight selection with Telegram-style pill framing
- immediate hold-and-drag selection when the page does not need scrolling
- scrollable pages with auto-scroll during external selection
- push/pop submenu navigation
- basic demo harness with test data

The original development harness entry point is:

- `mobile/ios/Packages/ContextMenuKit/Examples/ContextMenuDemoApp/ContextMenuDemoApp/Sources/RootViewController.swift`

The reusable library lives under:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit`

The Swift package manifest lives at:

- `mobile/ios/Packages/ContextMenuKit/Package.swift`

The checked-in example app lives at:

- `mobile/ios/Packages/ContextMenuKit/Examples/ContextMenuDemoApp`

The packaged example app entry point is:

- `mobile/ios/Packages/ContextMenuKit/Examples/ContextMenuDemoApp/ContextMenuDemoApp/Sources/RootViewController.swift`

Public API is intentionally limited to:

- `Model/`
- `Public/`
- the public SwiftUI modifier in `SwiftUI/View+ContextMenuSource.swift`
- the public SwiftUI custom-row helper in `SwiftUI/ContextMenuCustomRow+SwiftUI.swift`

Presentation, page layout, visuals, animation helpers, and source-resolution plumbing are internal implementation details.

## File-Level Architecture

### 1. Public model and configuration

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Model/ContextMenuTypes.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Public/ContextMenuSourcePortal.swift`

Implemented:

- `ContextMenuConfiguration` as the top-level configuration object
- `ContextMenuPage` as a page of menu content
- `ContextMenuItem` with five currently supported item kinds:
  - `.action`
  - `.back`
  - `.submenu`
  - `.custom`
  - `.separator`
- `ContextMenuBackAction`
- `ContextMenuCustomRow`
- `ContextMenuCustomRowSizing`
- `ContextMenuCustomRowInteraction`
- `ContextMenuCustomRowContext`
- `ContextMenuBackdropStyle`
- `ContextMenuVerticalPlacementBehavior`
- `ContextMenuStyle`
- `ContextMenuSourcePortal` for advanced source cloning and blur-cutout configuration

Important consequence:

- the public API is currently list-oriented, but list pages can now contain arbitrary custom rows
- there is no public custom-content page API yet
- vertical placement now preserves two behaviors:
  - `.screenBalanced` keeps the older screen-fit-first positioning logic
  - `.sourceAttached` chooses above/below first, then constrains height on that side and stays attached to the source
- `.sourceAttached` is the default

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:724-1082`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1920-2145`

Telegram has a richer item model internally because it supports both standard list items and fully custom content nodes.

### 2. Source interaction and overlay presentation

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Public/ContextMenuInteraction.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuPresenter.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuOverlayView.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Internal/ContextMenuPresentationSource.swift`

Implemented:

- `ContextMenuInteraction` for attaching menu triggers to a source view
- support for tap and long-press triggers
- an internal presenter and overlay host
- anchored positioning relative to the source view
- optional blur/dim backdrop
- appear/disappear animation
- forwarding long-press movement into menu selection after opening
- internal source-presentation resolution that turns a source portal into an anchor rect, portal source view, and cutout mask

Key responsibilities:

- attach the overlay directly to the source window
- compute panel position above or below the source
- keep the menu hidden before the first animation frame
- freeze the menu frame during dismiss to prevent layout jumps

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1218-1418`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1656-1772`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerImpl.swift:208-320`

The Telegram implementation is significantly more complex because it supports extracted content, controller content, reaction previews, and multiple source styles. `ContextMenuKit` reproduces the part of that path needed for a standalone menu overlay.

### 3. Menu stack and submenu host

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuNavigationView.swift`

Implemented:

- root page and pushed page stack
- panel size interpolation between previous and current submenu page
- horizontal submenu push/pop navigation
- directional back-swipe gesture
- gesture arbitration against other pan recognizers

Key behavior:

- only the current page and previous page remain visible during submenu transitions
- width and height interpolate between the two page sizes
- a directional pan recognizer handles interactive pop

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1409-1583`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1920-2145`

Telegram’s `NavigationContainer` is the key reference for:

- the glass container hierarchy
- interactive pop gesture policy
- container-size interpolation between pages

### 4. Page layout, rows, selection, and scrolling

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageView.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageElements.swift`

Implemented:

- row measurement and layout
- separators
- row icons, subtitles, badges, disclosure chevrons
- custom row hosting with selectable and content-handled interaction modes
- fixed-height and automatic custom-row sizing
- scrollable menu pages
- immediate selection overlay when scrolling is not needed
- external selection updates for long-press handoff
- auto-scroll while dragging through scrollable content
- shared selection highlight overlay

Key design decisions copied from Telegram:

- the selection highlight is not owned by each row
- instead, a single highlight view is positioned over the active row
- immediate hold-and-drag selection is enabled only when the page height fits without scrolling
- immediate hold-and-drag selection only captures selectable row regions, so custom content rows with internal buttons keep receiving touches
- scrollable pages keep normal scrolling behavior and receive selection from the external long-press path

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:916-1082`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1218`
- `submodules/Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift:1189-1248`

These files are the closest structural equivalent to Telegram’s standard action list behavior.
The custom-row extension is still intentionally narrower than Telegram’s fully custom page/content API.

### 5. Glass hierarchy, colors, highlight treatment, and badge rendering

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/ContextMenuTheme.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/ContextMenuGlassViews.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/UIView+ContextMenuMonochromaticEffect.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/ContextMenuPortalView.swift`

Implemented:

- title/subtitle/badge typography
- basic text and separator colors
- badge image rendering
- menu panel material effect
- glass container and inner glass background hierarchy
- monochromatic treatment helper used for the highlight overlay

Key structural choice:

- `ContextMenuPanelView` contains:
  - outer `ContextMenuGlassContainerView`
  - inner `ContextMenuGlassBackgroundView`
  - `contentView` hosted inside the glass background

This is intentionally modeled after Telegram’s production hierarchy rather than a simpler one-layer blur view, because Telegram’s structure is more stable with iOS 26 glass behavior.

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1410-1438`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1563-1583`
- `submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIViewController+Navigation.m:365-371`

The last reference is important: Telegram also ships a runtime luma clamp workaround that is **not** implemented in `ContextMenuKit` yet.

### 6. Animation helpers and directional pan recognizer

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Internal/ContextMenuAnimationSupport.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Internal/ContextMenuInteractivePanGestureRecognizer.swift`

Implemented:

- spring animation helper with Telegram-like timing constants
- alpha and basic transform helpers
- directional pan validation that rejects the wrong axis early

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1237-1240`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1444-1490`

## Implemented Behavior Mapping

This section describes what was implemented and where the design came from.

### A. Menu background container

Implemented in `ContextMenuKit`:

- `ContextMenuPanelView`
- `ContextMenuGlassContainerView`
- `ContextMenuGlassBackgroundView`

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/ContextMenuGlassViews.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuNavigationView.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1410-1438`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1563-1583`

Why this matters:

- Telegram does not rely on a single blur view
- it uses an outer glass container plus an inner glass background
- that structure appears to avoid several liquid-glass rendering issues

Current parity level:

- good structural parity
- missing Telegram’s runtime luma clamp workaround

### B. List row positioning and spacing

Implemented in `ContextMenuKit`:

- row measurement in `ContextMenuRowView.measuredSize`
- vertical padding before the first and after the last row
- consistent separator height
- fixed horizontal insets and highlight inset

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageView.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:934-986`

Current parity level:

- close for list rows and separators
- not yet generalized for Telegram-style custom items with their own internal layout contracts

### C. Selection highlight appearance and movement

Implemented in `ContextMenuKit`:

- one shared `selectionView`
- gray/black-white monochromatic pill treatment
- immediate placement on first appearance when starting from alpha `0`
- animated frame/corner-radius updates when moving between rows
- fade-out when clearing selection

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageView.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1055-1078`

Why the “immediate placement first, fade after” logic exists:

- Telegram avoids animating the first highlight frame from an empty or stale frame
- if the highlight is invisible, the frame is updated first and only opacity is animated in

Current parity level:

- good for list items
- no per-item custom highlight behavior hook yet

### D. Immediate hold-and-drag selection

Implemented in `ContextMenuKit`:

- a transparent `ContextMenuSelectionTouchView`
- enabled only when content fits without scrolling
- row UIControls are disabled while immediate selection is active
- a horizontal movement escape path lets submenu back-swipe take over

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageView.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1218`

Interpretation:

- Telegram enables pan-selection only when the menu page does not need scrolling
- the extracted port follows the same rule

Current parity level:

- good for the current list-page scope

### E. Scrollable content and gesture arbitration

Implemented in `ContextMenuKit`:

- `ContextMenuScrollView`
- normal scrolling when content exceeds available height
- external selection updates during auto-scroll
- back-swipe recognizer configured to yield to other `UIPanGestureRecognizer`s

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Page/ContextMenuPageView.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuNavigationView.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Internal/ContextMenuInteractivePanGestureRecognizer.swift`

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1456-1467`
- `submodules/Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift:1202-1213`

Why this matters:

- the menu’s own navigation gesture must not steal vertical scrolling
- Telegram’s recognizers are deliberately configured so other pan recognizers take precedence unless the back gesture clearly validates

Current parity level:

- workable and close enough for current list menus
- still simpler than Telegram’s full gesture matrix

### F. Appear animation

Implemented in `ContextMenuKit`:

- keep menu host alpha at `0` until animate-in starts
- animate menu alpha from `0`
- animate `transform.scale` from `0.01` to `1.0`
- animate position additively from source delta to zero
- fade in blur/dim backdrop separately

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuOverlayView.swift`

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1237-1240`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1369-1418`

Important note:

- the current extraction copied the non-extractable menu path
- Telegram also has a richer extracted-container animation path in `ContextControllerActionsStackNode.NavigationContainer.animateIn(...)`

Current parity level:

- good for a standalone source-anchored menu
- does not yet reproduce Telegram’s extracted-content morph from source bubble into the menu

### G. Dismiss animation

Implemented in `ContextMenuKit`:

- freeze the host frame before dismiss
- animate alpha to `0`
- animate `transform.scale` from `1.0` to `0.01`
- animate position additively back toward source delta
- animate blur/dim alpha separately
- avoid zeroing model alpha before layer animations complete

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuOverlayView.swift`

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1736-1772`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerExtractedPresentationNode.swift:1716-1735`

Current parity level:

- good for the current non-extracted path
- extracted-content return animation is not ported

### H. Submenu transitions

Implemented in `ContextMenuKit`:

- push/pop stack
- width/height interpolation between previous and next page
- horizontal motion
- previous-page alpha reduction

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuNavigationView.swift`

Telegram references:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1663-1690`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1729-1733`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:2093-2132`

Current parity level:

- functionally correct
- visually still simpler than Telegram, which also scales the transitioning page and applies a dim layer for depth

## What Was Intentionally Not Ported

The following Telegram systems were intentionally left out because they are tied to broader app infrastructure or exceed the current library scope.

### 1. Telegram presentation/theme system

Telegram source:

- `PresentationData`
- `PresentationTheme`
- `theme.contextMenu.*`

Status in `ContextMenuKit`:

- replaced with lightweight UIKit-driven color and spacing helpers

### 2. AsyncDisplayKit / Texture nodes

Telegram source:

- most context menu implementation is `ASDisplayNode` based

Status in `ContextMenuKit`:

- recreated with UIKit views only

### 3. Extractable content containers and lens transitions

Telegram source:

- `ContextControllerActionsStackNode.NavigationContainer.animateIn(...)`
- `ContextControllerActionsStackNode.NavigationContainer.animateOut(...)`

Status in `ContextMenuKit`:

- not ported
- current implementation animates a standalone menu host from source-relative position/scale only

### 4. Reaction preview, reaction strip, tip nodes, and controller-specific menu content

Telegram source:

- `ContextControllerExtractedPresentationNode.swift`
- `ContextControllerActionsStackNode.swift`
- `ReactionListContextMenuContent.swift`

Status in `ContextMenuKit`:

- not ported
- out of scope for the first isolated extraction

## Deferred Findings

These are the most important known gaps compared to Telegram.

### Finding 1: No custom or dynamic content page API yet

Current `ContextMenuKit` state:

- public `ContextMenuItem` supports `.action`, `.back`, `.submenu`, `.custom`, and `.separator` inside list pages
- there is still no public API for a fully custom or dynamic menu page outside that list-page model

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Model/ContextMenuTypes.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:639-721`
- `submodules/Components/ReactionListContextMenuContent/Sources/ReactionListContextMenuContent.swift:1248-1265`

Impact:

- the library cannot yet represent Telegram-style custom menu pages
- the “reacted/read by” page is the clearest reference feature that remains outside the public API

What would need to be added:

- a custom content item or page protocol
- a layout contract that reports both stable size and apparent height
- a way to request animated height updates from inside the custom page

Priority:

- highest

### Finding 2: Submenu transition depth is simpler than Telegram

Current `ContextMenuKit` state:

- submenu transitions only slide horizontally and adjust alpha

File:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuNavigationView.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1681-1688`
- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift:1729-1733`

Impact:

- the interaction works correctly
- the visual depth is flatter than Telegram’s production implementation

What Telegram also does:

- scales the transitioning page slightly
- applies dimming to the previous/current layers based on transition fraction

Priority:

- high if the goal is visual parity

### Finding 3: Glass stabilization workaround is incomplete

Current `ContextMenuKit` state:

- copied the glass container hierarchy
- copied monochromatic highlight treatment
- did **not** port Telegram’s luma clamp workaround

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Visuals/ContextMenuGlassViews.swift`

Telegram reference:

- `submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIViewController+Navigation.m:365-371`

Impact:

- behavior may still be less stable on certain backgrounds
- shadow/backdrop transitions may still expose iOS 26 liquid-glass glitches that Telegram explicitly patched

Priority:

- high if liquid-glass stability becomes a visible issue in more scenarios

### Finding 4: Long-press handoff threshold has been ported

Current `ContextMenuKit` state:

- UIKit and SwiftUI source handoff now matches Telegram's continuation model more closely
- external selection is seeded from movement updates, not from the initial long-press activation
- highlight forwarding only starts after animate-in has completed and the continued gesture has moved more than `4pt` vertically
- release only activates the highlighted row if that movement threshold was crossed

Files:

- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Public/ContextMenuInteraction.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/Presentation/ContextMenuOverlayView.swift`
- `mobile/ios/Packages/ContextMenuKit/Sources/ContextMenuKit/SwiftUI/ContextMenuSwiftUISourceBridge.swift`

Telegram reference:

- `submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerImpl.swift:281-322`
- `submodules/Display/Source/ContextGesture.swift:190-232`

Impact:

- the initial "menu opens with a highlighted item immediately" mismatch is resolved
- long-press release now behaves like Telegram when the user opens a menu but does not move far enough to enter item selection

## Recommended Next Implementation Order

If parity work continues, the recommended order is:

1. Add a custom page/content API.
2. Port Telegram-style submenu depth animation.
3. Add glass/luma stabilization work.
4. Decide whether extracted-source morphing is worth porting.

Reasoning:

- custom pages unlock the most important missing product capability
- submenu depth and glass stability most affect perceived quality
- long-press threshold tuning is lower risk and can follow after the structural work

## Practical Status Summary

Today, `ContextMenuKit` should be viewed as:

- a solid isolated clone of Telegram’s **list-based** context menu path
- good enough for menus composed of actions, separators, and submenus
- intentionally incomplete for Telegram’s most advanced custom-content menu pages

The existing implementation already contains the right structural foundation for further parity work:

- reusable menu model
- dedicated overlay host
- correct glass container layering
- correct highlight ownership model
- correct distinction between immediate selection and scrolling
- reusable submenu stack

The next major step is not polish. It is API expansion for custom content pages.
