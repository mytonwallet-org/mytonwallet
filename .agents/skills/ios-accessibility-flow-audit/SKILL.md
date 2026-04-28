---
name: ios-accessibility-flow-audit
description: Audit an iOS app flow for VoiceOver and general accessibility by driving the iOS Simulator, inspecting the accessibility hierarchy, and documenting findings screen by screen. Use when a user asks for an automated accessibility review, wants a flow walked in simulator, needs labels/traits/states verified, wants decorative or redundant elements identified for hiding from assistive tech, or asks for a findings document while moving through onboarding or product flows.
---

# iOS Accessibility Flow Audit

## Overview

Run a screen-by-screen accessibility review of an iOS flow with simulator automation. Prefer the accessibility tree over visual guesses, record findings before leaving each screen, and treat coordinate taps as justified fallbacks rather than the default interaction mode.

Use [`references/report-template.md`](references/report-template.md) when creating the findings document.

## Workflow

### 1. Preflight

- Read any repo-specific iOS instructions before launching the app.
- Set simulator and scheme defaults explicitly.
- Use the requested simulator model when the user names one.
- Launch the app into a stable starting state before auditing.
- Create the findings document early, usually before the first transition.

### 2. Audit the current screen

- Capture a screenshot and run `snapshot_ui` before interacting.
- Compare the visible UI against the accessibility hierarchy.
- List the key accessible elements for the current screen in the findings document.
- Identify findings before moving forward.
- Re-capture the hierarchy after any interaction that changes state.

### 3. Move to the next screen

- Prefer `tap` by accessibility `id` or `label`.
- If the intended control is missing from the accessibility tree, note that as a finding first.
- Only then use a coordinate tap as a fallback.
- If a bottom action does not respond, scroll it fully into view and retry before assuming the action is broken.

### 4. Finish in a stable state

- Complete the requested flow when feasible.
- Leave the app on a sensible post-flow screen.
- Summarize the highest-signal blockers and point to the findings document.

## What to check on every screen

- Missing interactive controls in the accessibility tree
- Decorative or redundant images exposed to assistive tech
- Raw asset names exposed as labels
- Static text used where a button, chip, segmented control, checkbox, or toggle should be exposed
- Missing state or value for selected, checked, disabled, expanded, or progress-tracking controls
- Inline links collapsed into non-interactive text
- Duplicate announcements caused by layered elements
- Titles that should be headings but are exposed as plain text
- Large bodies of copy exposed as one node when smaller sections would improve navigation
- Sensitive actions labeled too generically
- Custom keypads or input surfaces with unlabeled buttons
- Progress indicators or code-entry dots missing from the tree

Treat standard iOS system permission sheets separately: note them if they affect the flow, but do not count them as app-owned bugs unless the app-specific presentation around them is the problem.

## Findings document rules

- Add one section per screen.
- Write findings for the current screen before advancing.
- For each screen, include:
  - the screen name
  - the observed accessibility elements
  - numbered findings
- Keep findings concrete and tied to the current UI state.
- Call out blocking issues plainly when a screen-reader user cannot complete the task.

## Interaction rules

- Prefer the accessibility hierarchy over pixel interpretation.
- Use screenshots for visual confirmation, not as the primary source of truth for labels or states.
- Retry `snapshot_ui` if the tree is stale or missing after a transition.
- If `snapshot_ui` fails because of a transient overlay or bad translation state, nudge the UI minimally, then retry.
- Validate state changes in the accessibility tree, not only by appearance.

## Common failure patterns

- Agreement rows split into a static text node plus a separate selected image instead of one checkbox-like control
- Checklist rows exposed as generic buttons with no checked state
- Seed phrase lists fragmented into separate number and word nodes
- Verification answer chips exposed as plain text instead of controls
- Passcode keypads exposed as unlabeled buttons
- Success screens missing heading semantics

When one of these appears, document the exact manifestation on the current screen instead of pasting a generic warning.
