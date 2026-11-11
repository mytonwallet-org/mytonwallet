import assert from 'node:assert/strict';
import test from 'node:test';

import { findTitleProblems, fixTitle, RULES } from './checkPrTitle.mjs';

// Subjects from `master`, with the ` (#1234)` that the squash merge appends removed, unless noted
const VALID_TITLES = [
  '[Android] Token / Chart: Fix endless chart loading for tokens opened from search',
  '[All] EVM / Swap: Fix native sales sent without enough left for gas',
  '[Perf] [SDK] TON Connect: Fix slow transaction requests behind background provider requests',
  '[All] Perps: Fix a second deposit after a rejected leverage change; Fix orders signed without a verified market',
  '[Classic] Unlock: Fix "Wrong password" for a device that lost its wallet data; Log storage loss found at boot',
  '[iOS] Buy/Sell: Fix disclaimer rendering artifacts and button shape',
  '[iOS] Perps v0.2: Fix trading, funding recovery, and screen interactions',
  '[Classic] Agent: Fix various UI issues (follow up)',
  '[Refactoring] iOS / Agent: Split AgentVC into extension files by concern',
  '[iOS] macOS: Work around Metal cache suspension kill',
  '[Classic] Extension: Drop the unused `webRequest` permission',
  '[Refactoring] Create mixin for `:active` style optimization',
  'Analytics: Fix Gram Web release blocked by the staging origin in the bundle',
  'Bump version to 26.11.1',
  'Revert "[iOS] Top Tabs: Add glass selection capsule"',
  // The examples in CODESTYLE.md
  'Message / Round Video: Fix progressive loading',
  '[SEO] Replace `meta[noindex]` with `link[canonical]`',
  '[Refactoring] Fix @typescript-eslint/await-thenable errors',
  // This pull request
  '[CI] PR Title: Check the commit format of pull request titles',
  // Not from `master`: imperative verbs that end in "ed" or share their past form
  '[iOS] Swap: Speed up quote loading',
  '[Classic] Dapps: Embed the confirmation in the page',
  '[All] Settings: Reset the slippage when the token changes',
  // Not from `master`: code names in the area, with a colon inside the backticks
  '[Classic] API / `callApi`: Fix transport-error handling',
  '[Classic] Styles / `:active`: Fix stuck pressed state on touch screens',
  // Not from `master`: a semicolon inside backticks is code, not a task separator
  '[CI] Scripts: Fix `a; b` parsing',
];

// Every broken title with the rules it breaks, the title `fixTitle` makes of it and what that still breaks
const INVALID_TITLES = {
  '[Android] fix/TokenChart: Fix endless chart loading for tokens opened from search': {
    problems: ['fix-marker'],
    fixed: '[Android] TokenChart: Fix endless chart loading for tokens opened from search',
    remaining: [],
  },
  '[Android] Fix/TokenTrade: Fix method row hidden in short windows': {
    problems: ['fix-marker'],
    fixed: '[Android] TokenTrade: Fix method row hidden in short windows',
    remaining: [],
  },
  '[All] fix/Permissions: pass gaslimit exclicitly to prevent underestimate in hidden gas_estimate': {
    problems: ['fix-marker', 'description-case'],
    fixed: '[All] Permissions: Pass gaslimit exclicitly to prevent underestimate in hidden gas_estimate',
    remaining: [],
  },
  '[iOS] (fix) Toolbar: Update defaults and scan icon': {
    problems: ['fix-marker'],
    fixed: '[iOS] Toolbar: Update defaults and scan icon',
    remaining: [],
  },
  '[iOS] (experimental fix) Recover shared toolbar glass tint after interrupted transitions': {
    problems: ['fix-marker', 'missing-area'],
    fixed: '[iOS] Recover shared toolbar glass tint after interrupted transitions',
    remaining: ['missing-area'],
  },
  '[iOS] fix/Rename Swap entry points to Trade': {
    problems: ['fix-marker', 'missing-area'],
    fixed: '[iOS] Rename Swap entry points to Trade',
    remaining: ['missing-area'],
  },
  '[All] UTXO: fix/bch addr format': {
    problems: ['fix-marker', 'description-case'],
    fixed: '[All] UTXO: Bch addr format',
    remaining: [],
  },
  '[Fix] Price native Max swaps and mark failed deposits in history': {
    problems: ['fix-marker', 'missing-area'],
    fixed: 'Price native Max swaps and mark failed deposits in history',
    remaining: ['missing-area'],
  },
  '[iOS] fix: Crash when low power mode is changed': {
    problems: ['conventional-commit'],
    fixed: '[iOS] fix: Crash when low power mode is changed',
    remaining: ['conventional-commit'],
  },
  'fix: restore icon glyphs and use TTF on iOS': {
    problems: ['conventional-commit'],
    fixed: 'fix: restore icon glyphs and use TTF on iOS',
    remaining: ['conventional-commit'],
  },
  'chore: logs': {
    problems: ['conventional-commit'],
    fixed: 'chore: logs',
    remaining: ['conventional-commit'],
  },
  '[Classic] Deeplinks: Fixed some commands being available for view-only accounts': {
    problems: ['past-tense'],
    fixed: '[Classic] Deeplinks: Fix some commands being available for view-only accounts',
    remaining: [],
  },
  '[Android] WalletCardView: Added Blur Views': {
    problems: ['past-tense'],
    fixed: '[Android] WalletCardView: Add Blur Views',
    remaining: [],
  },
  '[Classic]Card: Fixed opening Explore when opening Portfolio': {
    problems: ['tag-spacing', 'past-tense'],
    fixed: '[Classic] Card: Fix opening Explore when opening Portfolio',
    remaining: [],
  },
  '[iOS][CI] Pause Preview external TestFlight distribution': {
    problems: ['tag-spacing', 'missing-area'],
    fixed: '[iOS] [CI] Pause Preview external TestFlight distribution',
    remaining: ['missing-area'],
  },
  '[Air][Classic] Agent: Show MyPulse news as a post in its chat': {
    problems: ['tag-spacing'],
    fixed: '[Air] [Classic] Agent: Show MyPulse news as a post in its chat',
    remaining: [],
  },
  '[iOS] Fix stray plus after delayed Agent consent': {
    problems: ['missing-area'],
    fixed: '[iOS] Fix stray plus after delayed Agent consent',
    remaining: ['missing-area'],
  },
  '[iOS] [Chore] Remove disabled tab customization screen': {
    problems: ['missing-area'],
    fixed: '[iOS] [Chore] Remove disabled tab customization screen',
    remaining: ['missing-area'],
  },
  '[iOS, Android] Fix mtw://transfer deeplinks in IAB on iOS and Android': {
    problems: ['missing-area'],
    fixed: '[iOS, Android] Fix mtw://transfer deeplinks in IAB on iOS and Android',
    remaining: ['missing-area'],
  },
  'Support LI.FI Permit2 swap signing': {
    problems: ['missing-area'],
    fixed: 'Support LI.FI Permit2 swap signing',
    remaining: ['missing-area'],
  },
  '[Classic] Perps: utilize enriched info of /activities': {
    problems: ['description-case'],
    fixed: '[Classic] Perps: Utilize enriched info of /activities',
    remaining: [],
  },
  ' [Classic] Perps: utilize enriched info of /activities': {
    problems: ['whitespace', 'description-case'],
    fixed: '[Classic] Perps: Utilize enriched info of /activities',
    remaining: [],
  },
  '[Classic] NFT: Fix  menu ordering; add "Hide and Report" row': {
    problems: ['whitespace', 'task-case'],
    fixed: '[Classic] NFT: Fix menu ordering; Add "Hide and Report" row',
    remaining: [],
  },
  '[iOS] Portfolio: Fix pie chart range labels and show single data point ': {
    problems: ['whitespace'],
    fixed: '[iOS] Portfolio: Fix pie chart range labels and show single data point',
    remaining: [],
  },
  '[iOS] Misc fixups for chain icons etc.': {
    problems: ['missing-area', 'trailing-punctuation'],
    fixed: '[iOS] Misc fixups for chain icons etc',
    remaining: ['missing-area'],
  },
  '[iOS] Explore: Fix/Use glass for connected dapps and fix label sizing': {
    problems: ['fix-marker'],
    fixed: '[iOS] Explore: Use glass for connected dapps and fix label sizing',
    remaining: [],
  },
  // Not from `master`
  '[Classic] feat(swap): Add a slippage presets row': {
    problems: ['conventional-commit'],
    fixed: '[Classic] feat(swap): Add a slippage presets row',
    remaining: ['conventional-commit'],
  },
  '[iOS] Wallet: Made the balance screen faster': {
    problems: ['past-tense'],
    fixed: '[iOS] Wallet: Make the balance screen faster',
    remaining: [],
  },
  '[iOS] dapps: Fix the title skeletons': {
    problems: ['area-case'],
    fixed: '[iOS] Dapps: Fix the title skeletons',
    remaining: [],
  },
  '[iOS] Dapps:Fix the title skeletons': {
    problems: ['colon-spacing'],
    fixed: '[iOS] Dapps: Fix the title skeletons',
    remaining: [],
  },
  '[iOS] Dapps: Fix the title skeletons;': {
    problems: ['trailing-punctuation'],
    fixed: '[iOS] Dapps: Fix the title skeletons',
    remaining: [],
  },
  'Bump version to 26.11': {
    problems: ['missing-area'],
    fixed: 'Bump version to 26.11',
    remaining: ['missing-area'],
  },
  '[iOS] Fix: Crash on launch': {
    problems: ['fix-marker'],
    fixed: '[iOS] Crash on launch',
    remaining: ['missing-area'],
  },
  '[Fix] [iOS ]Wallet / fix:   added a row.;': {
    problems: ['whitespace', 'tag-spacing', 'fix-marker', 'description-case', 'trailing-punctuation'],
    fixed: '[iOS] Wallet: Add a row',
    remaining: [],
  },
  '[CI] Scripts: Fix `a`; b': {
    problems: ['task-case'],
    fixed: '[CI] Scripts: Fix `a`; B',
    remaining: [],
  },
  // Nothing is left once the marker goes, so the workflow keeps the title
  '[Fix]': {
    problems: ['tag-spacing', 'fix-marker', 'missing-area', 'description-case'],
    fixed: '',
    remaining: ['missing-area', 'description-case'],
  },
  // What only a person can correct: a past form missing from the table, an area or a description that
  // does not start with a letter
  '[iOS] Wallet: Tweaked the balance screen': {
    problems: ['past-tense'],
    fixed: '[iOS] Wallet: Tweaked the balance screen',
    remaining: ['past-tense'],
  },
  '[iOS] /dapps: Fix the deeplink handling': {
    problems: ['area-case'],
    fixed: '[iOS] /dapps: Fix the deeplink handling',
    remaining: ['area-case'],
  },
  '[iOS] Wallet: 2 fixes for the balance screen': {
    problems: ['description-case'],
    fixed: '[iOS] Wallet: 2 fixes for the balance screen',
    remaining: ['description-case'],
  },
};

// The rules that may still fail after `fixTitle`: what needs a person, see the last entries above
const UNFIXABLE = new Set(['missing-area', 'conventional-commit', 'past-tense', 'area-case', 'description-case']);

test('accepts titles in the commit format', () => {
  for (const title of VALID_TITLES) {
    assert.deepEqual(findTitleProblems(title), [], title);
  }
});

test('names every broken rule', () => {
  for (const [title, { problems }] of Object.entries(INVALID_TITLES)) {
    assert.deepEqual(findTitleProblems(title).sort(), [...problems].sort(), JSON.stringify(title));
  }
});

test('describes every rule it can report', () => {
  const reported = new Set(Object.values(INVALID_TITLES).flatMap(({ problems }) => problems));
  assert.deepEqual([...reported].sort(), Object.keys(RULES).sort());
});

test('fixes what it can and leaves the rest', () => {
  for (const [title, { fixed, remaining }] of Object.entries(INVALID_TITLES)) {
    assert.equal(fixTitle(title), fixed, JSON.stringify(title));
    assert.deepEqual(findTitleProblems(fixed).sort(), [...remaining].sort(), JSON.stringify(fixed));
    assert.ok(remaining.every((problem) => UNFIXABLE.has(problem)), JSON.stringify(title));
  }
});

test('leaves titles in the commit format as they are', () => {
  for (const title of VALID_TITLES) {
    assert.equal(fixTitle(title), title);
  }

  // A space inside the brackets breaks no rule, but goes along with a fix
  assert.equal(fixTitle('[All ] UTXO: fix/bch addr format'), '[All] UTXO: Bch addr format');
});

test('fixes a title in one pass', () => {
  for (const title of [...VALID_TITLES, ...Object.keys(INVALID_TITLES)]) {
    assert.equal(fixTitle(fixTitle(title)), fixTitle(title), JSON.stringify(title));
  }
});
