# Import Wallet Secret Phrase Accessibility Review

Date: 2026-04-16

Scope: Import wallet using secret phrase flow, MyTonWallet_AirOnly, iPhone 17 Pro

Status: completed

## Method

- Navigate the app with simulator automation.
- Inspect each screen with the accessibility hierarchy before moving forward.
- Record findings screen by screen before advancing.

## Findings

### Screen 1: Welcome / Intro

Observed accessibility elements:
- Static text: `MyTonWallet`
- Static text: `Securely store crypto and make blockchain payments at the speed of light.`
- Button: `More about MyTonWallet ›`
- Button: `I agree to use the wallet responsibly`
- Button: `Create New Wallet`
- Button: `Import Existing Wallet`

Findings:
1. The screen title `MyTonWallet` is exposed as plain static text rather than a heading, so VoiceOver users do not get a heading landmark on the first screen of the flow.
2. The consent row is exposed as a generic button with no explicit checked or unchecked state. After toggling it, the downstream buttons become enabled, but the accessibility tree still does not announce that the consent itself changed state.
3. The consent row also carries a secondary `Use Responsibly` action. In practice, its consent behavior and legal-content action compete inside one accessibility target, which makes the control semantics harder to predict than a separate checkbox plus link.

### Screen 2: Use Responsibly

Observed accessibility elements:
- Back button: `Back`
- Static text: `Use Responsibly`
- Static text: long disclaimer body
- Button: `Terms of Use`
- Button: `Privacy Policy`

Findings:
1. The title `Use Responsibly` is exposed as plain static text rather than a heading.
2. The full disclaimer body is exposed as one large static-text element. It is readable, but it is harder for VoiceOver users to review paragraph by paragraph or relocate a specific section.

### Screen 3: Import Existing Wallet Picker

Observed accessibility elements:
- Group: `dismiss popup`
- Group: `dismiss popup`
- Heading: `Import Wallet`
- Button: `close`
- Button: `12/24 Secret Words`
- Button: `Ledger`
- Button: `View Any Address`

Findings:
1. The sheet exposes two separate `dismiss popup` groups in the accessibility tree before the actual sheet content. They appear redundant and add extra swipe stops ahead of the actionable options.

### Screen 4: Enter Secret Words

Observed accessibility elements:
- Back button: `Back`
- Static text: `Enter Secret Words`
- Static text: import instructions
- Button: `Paste from Clipboard`
- Static-text indices: `1` through `24`
- Text fields: 24 unlabeled inputs with empty values
- Disabled button: `Continue`

Findings:
1. The screen title `Enter Secret Words` is exposed as plain static text rather than a heading.
2. All 24 input fields are exposed with no accessible labels. VoiceOver users encounter a long series of blank text fields and cannot tell which word position each field belongs to. This is a blocking issue for manual seed-phrase entry.
3. The word numbers are separate static-text elements rather than part of the corresponding field labels, so the field context is fragmented even though the visible UI pairs each index with an input.

### Screen 5: Set Passcode

Observed accessibility elements:
- Static text: `Wallet is ready!`
- Static text: `Create a code to protect it`
- Static text: `Enter code`
- Text area: `Enter code` with bullet value after input
- Buttons: `0` through `9`
- Button: `Delete`

Findings:
1. The step title content is exposed as plain static text rather than a heading, so this major transition in the flow has no heading landmark.

### Screen 6: Confirm Passcode

Observed accessibility elements:
- Static text: `Wallet is ready!`
- Static text: `Create a code to protect it`
- Static text: `Enter your code again`
- Text area: `Enter your code again`
- Buttons: `0` through `9`
- Button: `Delete`

Findings:
1. The confirmation step also lacks heading semantics for its primary title and prompt.

### Screen 7: Import Success

Observed accessibility elements:
- Heading: `All Set!`
- Static text: success message body
- Button: `Open Wallet`

Findings:
1. No app-owned accessibility issue stood out on this screen during this run.
