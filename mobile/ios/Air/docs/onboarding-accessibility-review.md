# Onboarding Accessibility Review

Date: 2026-04-15

Scope: native iOS onboarding flow for creating a new wallet on `MyTonWallet_AirOnly`, audited on the `iPhone 17 Pro` simulator.

Status: in progress

## Method

- Navigate the app with simulator automation.
- Inspect each screen with the simulator accessibility hierarchy before moving forward.
- Log findings screen by screen so issues stay tied to the exact UI state where they appear.

## Findings

### Screen 1: Welcome / Intro

Observed accessibility elements:
- Image: `IntroLogo`
- Static text: `MyTonWallet`
- Static text: `Securely store crypto and make blockchain payments at the speed of light.`
- Button: `More about MyTonWallet ›`
- Static text: `I agree to use the wallet responsibly`
- Disabled button: `Create New Wallet`
- Disabled button: `Import Existing Wallet`

Findings:
1. Decorative logo is exposed to assistive tech with the raw asset name `IntroLogo`. This reads like implementation detail, duplicates the nearby product name, and should likely be hidden from accessibility.
2. The agreement control is not exposed as one interactive control. In the unchecked state, VoiceOver sees only static text for `I agree to use the wallet responsibly`. In the checked state, the checkmark appears separately as an image labeled `Selected`. The row never becomes a single checkbox, toggle, or selected button with a clear state/value.
3. The inline `use the wallet responsibly` link is not separately reachable from the accessibility tree. The whole row collapses into one static text node, so a screen-reader user has no discoverable path to open the responsible-use content without also depending on an unlabeled gesture implementation.

### Screen 2: Use Responsibly

Observed accessibility elements:
- Back button: `Back`
- Static text: `Use Responsibly`
- Static text: long disclaimer body
- Button: `Terms of Use`
- Button: `Privacy Policy`

Findings:
1. The full disclaimer body is exposed as one large static-text element instead of smaller paragraphs or sections. It remains readable, but it is harder for VoiceOver users to pause, re-find a specific paragraph, or navigate the content in smaller chunks.

### Screen 3: Create Backup

Observed accessibility elements:
- Back button: `Back`
- Static text: `Create Backup`
- Button: `On the next screen you will see the secret words. Write them down in the correct order and store in a secure place.`
- Button: `They allow to open your wallet if you lose your password or access to this device.`
- Button: `If anybody else sees these words your funds may be stolen. Do not send it to anyone, not even developers or technical support.`
- Disabled button: `Go to Words`

Findings:
1. The three acknowledgement rows are exposed as generic buttons with only their body copy as labels. They do not announce that they are checklist items, and they do not expose checked or unchecked state.
2. The visible circular indicators are not represented in the accessibility tree in the unchecked state. A VoiceOver user gets no explicit progress signal while working through the required confirmations.

### Screen 4: Recovery Phrase / 24 Words

Observed accessibility elements:
- Back button: `Back`
- Heading: `24 Words`
- Static text: recovery-phrase instructions
- Static text: warning copy
- Button: `Copy to Clipboard`
- Recovery words exposed as separate static-text elements for each index and each word
- Button: `Let’s Check`
- Button: `Open wallet without checking`

Findings:
1. The recovery phrase is fragmented into separate accessibility elements for each number and each word. Instead of 24 list items like `1. taste`, VoiceOver users must traverse 48 separate nodes and reconstruct each pair mentally.
2. `Copy to Clipboard` is too generic for a sensitive action on this screen. The accessible label does not say that it copies the secret recovery phrase, which increases ambiguity and weakens the warning context for screen-reader users.

### Screen 5: Recovery Phrase Check

Observed accessibility elements:
- Back button labeled with previous title: `24 Words`
- Static text: `Let’s Check`
- Static text: instructions for words `3, 5, 10`
- Static text nodes for the prompt indices
- Static text nodes for each answer choice

Findings:
1. The answer choices are not exposed as interactive controls. Each selectable word appears as static text in the accessibility tree, even though the user must tap one option in each group to continue. This is a blocking issue for VoiceOver users.
2. The verification content is fragmented into loose text nodes instead of grouped question rows, so the relationship between `3.` / `5.` / `10.` and their candidate words is harder to follow non-visually.
3. The screen title `Let’s Check` is exposed as plain static text rather than a heading, which makes heading navigation less consistent than the previous `24 Words` screen.

### Screen 6: Set Passcode

Observed accessibility elements:
- Static text: `Wallet is ready!`
- Static text: `Create a code to protect it`
- Static text: `Enter code`
- Keypad buttons present in the accessibility tree with `AXLabel: null`

Findings:
1. The passcode keypad buttons have no accessibility labels at all. VoiceOver users would encounter a grid of unlabeled buttons and would not know which digits they are entering. This is a blocking issue.
2. The entered-code indicators are not exposed in the accessibility tree, so there is no non-visual feedback about how many digits have been entered.

### Screen 7: Confirm Passcode

Observed accessibility elements:
- Static text: `Wallet is ready!`
- Static text: `Create a code to protect it`
- Static text: `Enter your code again`
- Keypad buttons present in the accessibility tree with `AXLabel: null`

Findings:
1. The confirmation keypad repeats the same unlabeled-button issue, so the user is forced through two consecutive screens of inaccessible number entry.
2. The confirmation progress dots are still absent from the accessibility tree, leaving no non-visual way to tell whether the repeated code entry is complete or mismatched.

### Screen 8: Wallet Creation Success

Observed accessibility elements:
- Static text: `All Set!`
- Static text: success message body
- Button: `Open Wallet`

Findings:
1. `All Set!` is exposed as plain static text rather than a heading. The screen remains usable, but heading navigation is inconsistent with the one screen in this flow that correctly exposed a heading.

### Screen 9: Post-Onboarding Notification Permission Prompt

Observed accessibility elements:
- Static text: `“MyTonWallet” Would Like to Send You Notifications`
- Static text: iOS notification-permission explainer
- Button: `Don’t Allow`
- Button: `Allow`

Findings:
1. No app-owned accessibility issue observed here. This is the standard iOS system permission sheet, and its primary controls are properly exposed.
