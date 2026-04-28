# Home Tab Accessibility Review

Date: 2026-04-16

Scope: Home tab (`HomeVC`), `MyTonWallet_AirOnly`, iPhone 17 Pro simulator

Status: completed

## Method

- Launch the configured account on the simulator.
- Inspect each Home tab state with the accessibility hierarchy before moving on.
- Stay within Home tab content only, including the in-tab `Assets` and `Collectibles` switch, without opening other tabs or sheets.

## Findings

### Screen 1: Home tab, top header and quick actions

Observed accessibility elements:
- Group: unlabeled nav bar
- Static text: `MyTonWallet`
- Static text: `$0.025` (duplicated)
- Static text: `MyTonWallet`
- Button: `+ 1.06% · $0.00026`
- Button with no label in the header/card area
- Images: `ArrowUpDown`, `chain_ton`, `chain_tron`, `chain_solana`, `ArrowUpDownSmall`, `PromoCardOverlay`, `PromoCardBg`
- Static text: `Fund`, `Send`, `Swap`, `Earn`

Findings:
1. The Home title is exposed as plain static text rather than a heading, and the top nav bar is surfaced as an unlabeled group. During this run, the visible icon-only controls in that area did not appear as separate accessible buttons.
2. The balance header announces the same balance twice and also exposes multiple decorative images by raw asset name. This adds a lot of noisy swipe stops before users reach actionable content.
3. There is an unlabeled button in the upper-right area of the wallet card/header, so VoiceOver users get an actionable element with no name.
4. The quick-action row is not exposed as buttons. VoiceOver only sees `Fund`, `Send`, `Swap`, and `Earn` as static text labels.

### Screen 2: Assets segment and token list

Observed accessibility elements:
- Static text: `Assets` (duplicated)
- Static text: `Collectibles` (duplicated)
- Image: `SegmentedControlArrow`
- Token rows exposed as separate static texts for name, price, balance, and fiat value
- Button: `More`
- Static text: `Show All Assets`
- Static text: `10`

Findings:
1. The in-tab `Assets` / `Collectibles` switch is not exposed as a segmented control or as buttons with selected state. Both labels are duplicated, and the decorative arrow is announced separately.
2. Each asset row is fragmented into multiple static-text nodes instead of one coherent row element. Users have to assemble token name, APY, holdings, and fiat value manually.
3. The `Show All Assets` row is also fragmented. Its title and count badge are plain static text, while the overflow menu is a separate button, so the row is not presented as one clear control.

### Screen 3: Recent activity

Observed accessibility elements:
- Static text dates such as `January 18`, `August 22, 2025`, and `August 11, 2025`
- Activity rows split into separate static texts for status, amount, counterparty/time, and fiat value
- NFT activity rows additionally split title and collection name into separate static texts

Findings:
1. Activity section dates are exposed as plain static text rather than headings, so VoiceOver users cannot jump between activity groups with heading navigation.
2. Each transaction row is broken into multiple swipe stops instead of one concise summary element, which makes activity review slow and hard to follow.
3. NFT-related activity becomes especially verbose because the NFT title and collection name are exposed as separate text nodes on top of the already fragmented transaction metadata.

### Screen 4: Collectibles segment

Observed accessibility elements:
- Static text: `Assets` (duplicated)
- Static text: `Collectibles` (duplicated)
- Compact collectible card shown visually
- Activity content below continues to use fragmented static-text rows

Findings:
1. The `Collectibles` state inherits the same missing segment semantics: no announced selected/unselected state, duplicated labels, and no segmented-control behavior in the accessibility tree.
2. In this state the tree still does not surface a clearly self-describing collectible item before dropping back into activity content, so the visible collectible card is not discoverable as cleanly as the visual UI suggests.
