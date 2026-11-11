// Pull requests merge as squash commits that take the pull request title as their subject, so the title
// is the line `master` keeps. This holds it to the format in CODESTYLE.md, "Commit Messages".
export const EXPECTED_SHAPE = '[Tag] Component / Area: Imperative description';
const EXAMPLE = '[Android] Token / Chart: Fix squashed price chart on tablet';

// Titles that tooling writes rather than a person: the release bot's version bump (the same pattern
// `bump-approval.yml` approves) and GitHub's Revert button, which quotes the reverted title as it was.
const GENERATED_TITLES = [
  /^Bump version to \d+\.\d+\.\d+$/,
  /^Revert ".+"$/,
];

// Tags that name the kind of change rather than a platform, and so may stand without an area, as in
// `[Refactoring] Fix @typescript-eslint/await-thenable errors`
const KIND_TAGS = new Set(['Refactoring', 'Perf', 'Size', 'Dev', 'SEO', 'CI', 'Security']);

const FIX_MARKERS = new Set(['fix', 'feat', 'feature', 'bugfix', 'hotfix']);
// `fix/` and the like, or `(fix)` and `(experimental fix)`, in front of the area or the description
const FIX_MARKER_PREFIX = /^(?:(?:fix|feat|feature|bugfix|hotfix)\/|\((?:[^)]*\s)?fix\))/i;
const CONVENTIONAL_PREFIX = /^(?:fix|feat|chore|docs|refactor|perf|test|build|ci|style|revert)(?:\([^)]*\))?!?:/;
// A semicolon outside backticks, so code such as `a; b` stays within one task
const TASK_SEPARATOR = /;(?=(?:[^`]*`[^`]*`)*[^`]*$)/;
// Imperative verbs that end in "ed" as well: Embed, Proceed, Speed
const NOT_PAST_TENSE = /eed$|^(?:Embed|Shed|Shred)$/;
// Irregular past forms that are never the imperative; `Set`, `Put` and `Read` are both and pass
const IRREGULAR_PAST_TENSE = new Set([
  'Made', 'Built', 'Rebuilt', 'Wrote', 'Rewrote', 'Ran', 'Sent', 'Brought', 'Kept', 'Found', 'Took', 'Gave',
  'Got', 'Began', 'Chose', 'Broke', 'Froze', 'Hid', 'Did', 'Redid', 'Undid', 'Went', 'Held', 'Drew', 'Spent',
  'Thought', 'Told', 'Taught',
]);
// The imperative that `fixTitle` puts in place of a past form; a past form missing here stays for the author
const IMPERATIVE_BY_PAST_TENSE = new Map([
  ['Fixed', 'Fix'], ['Added', 'Add'], ['Removed', 'Remove'], ['Updated', 'Update'], ['Changed', 'Change'],
  ['Improved', 'Improve'], ['Moved', 'Move'], ['Renamed', 'Rename'], ['Replaced', 'Replace'],
  ['Refactored', 'Refactor'], ['Implemented', 'Implement'], ['Introduced', 'Introduce'], ['Enabled', 'Enable'],
  ['Disabled', 'Disable'], ['Allowed', 'Allow'], ['Prevented', 'Prevent'], ['Restored', 'Restore'],
  ['Reverted', 'Revert'], ['Adjusted', 'Adjust'], ['Used', 'Use'], ['Supported', 'Support'], ['Created', 'Create'],
  ['Deleted', 'Delete'], ['Showed', 'Show'],
  ['Made', 'Make'], ['Built', 'Build'], ['Rebuilt', 'Rebuild'], ['Wrote', 'Write'], ['Rewrote', 'Rewrite'],
  ['Ran', 'Run'], ['Sent', 'Send'], ['Brought', 'Bring'], ['Kept', 'Keep'], ['Found', 'Find'], ['Took', 'Take'],
  ['Gave', 'Give'], ['Got', 'Get'], ['Began', 'Begin'], ['Chose', 'Choose'], ['Broke', 'Break'],
  ['Froze', 'Freeze'], ['Hid', 'Hide'], ['Did', 'Do'], ['Redid', 'Redo'], ['Undid', 'Undo'], ['Went', 'Go'],
  ['Held', 'Hold'], ['Drew', 'Draw'], ['Spent', 'Spend'], ['Thought', 'Think'], ['Told', 'Tell'],
  ['Taught', 'Teach'],
]);

export const RULES = {
  'whitespace': 'Use single spaces, with none at the start or the end of the title',
  'tag-spacing': 'Put exactly one space after every `]`: `[iOS] [CI] Area: …`, not `[iOS][CI] Area: …`',
  'conventional-commit': 'Do not use Conventional Commits prefixes such as `fix:`, `feat:` or `chore:`; '
    + 'name the area instead',
  'fix-marker': 'Do not mark a fix with `fix/`, `feat/`, `(fix)` or a `[Fix]` tag; '
    + 'a description that starts with `Fix` is the only fix marker',
  'missing-area': 'Name the component or area before a colon; only `[Refactoring]`, `[Perf]`, `[Size]`, '
    + '`[Dev]`, `[SEO]`, `[CI]` and `[Security]` titles may leave it out',
  'area-case': 'Start the area with a capital letter',
  'colon-spacing': 'Put exactly one space after the colon that ends the area',
  'description-case': 'Start the description with a capital letter or a backtick',
  'past-tense': 'Write the description in the imperative mood: `Fix`, `Add`, not `Fixed`, `Added`',
  'task-case': 'Start every task after a semicolon with a capital letter or a backtick',
  'trailing-punctuation': 'Do not end the title with a period or a semicolon',
};

// A capital, a backtick, or a name spelled with a lowercase first letter, such as iOS or macOS
function startsCapitalized(text) {
  return /^(?:[A-Z`]|[a-z]+[A-Z])/.test(text);
}

export function findTitleProblems(title) {
  if (GENERATED_TITLES.some((pattern) => pattern.test(title))) return [];

  const problems = new Set();
  if (title !== title.trim() || /\s{2}|[^\S ]/.test(title)) problems.add('whitespace');

  // Read on from the trimmed text, so a stray space reports once rather than under every rule after it
  let rest = title.trim();
  const tags = [];
  for (let match = /^\[([^[\]]+)\]/.exec(rest); match; match = /^\[([^[\]]+)\]/.exec(rest)) {
    tags.push(match[1]);
    rest = rest.slice(match[0].length);
    if (!rest.startsWith(' ')) problems.add('tag-spacing');
    rest = rest.trimStart();
  }

  if (CONVENTIONAL_PREFIX.test(rest)) {
    problems.add('conventional-commit');
    return [...problems];
  }

  // A marker is cut off once reported, so the area and the description behind it are still checked
  const stripFixMarker = (text) => {
    const marker = FIX_MARKER_PREFIX.exec(text);
    if (!marker) return text;

    problems.add('fix-marker');
    return text.slice(marker[0].length).trimStart();
  };

  if (tags.some((tag) => FIX_MARKERS.has(tag.toLowerCase()))) problems.add('fix-marker');
  rest = stripFixMarker(rest);

  // The colon that ends an area is followed by the description, which keeps `mtw://` out of it. An
  // area may name code in backticks, as in ``API / `callApi`: …``, and a colon inside them is not the end.
  let description = rest;
  const areaMatch = /^((?:[^:`]|`[^`]*`)+):(?=\s|[A-Z`]|$)(.*)$/.exec(rest);
  if (areaMatch) {
    const [, area, afterColon] = areaMatch;
    description = afterColon.trimStart();

    if (area.split('/').some((segment) => FIX_MARKERS.has(segment.trim().toLowerCase()))) {
      problems.add('fix-marker');
    } else if (!startsCapitalized(area) && !/^\d/.test(area)) {
      problems.add('area-case');
    }

    if (!afterColon.startsWith(' ')) problems.add('colon-spacing');
  } else if (!tags.length || !tags.every((tag) => KIND_TAGS.has(tag))) {
    problems.add('missing-area');
  }

  description = stripFixMarker(description);
  if (!startsCapitalized(description)) problems.add('description-case');

  const firstWord = /^[A-Za-z]+/.exec(description)?.[0] ?? '';
  if (
    (/^[A-Z][a-z]+ed$/.test(firstWord) && !NOT_PAST_TENSE.test(firstWord)) || IRREGULAR_PAST_TENSE.has(firstWord)
  ) {
    problems.add('past-tense');
  }

  if (description.split(TASK_SEPARATOR).slice(1).some((task) => task.trim() && !startsCapitalized(task.trim()))) {
    problems.add('task-case');
  }

  if (/[.;]$/.test(title.trim())) problems.add('trailing-punctuation');

  return [...problems];
}

// The colon that ends an area, as `findTitleProblems` reads it
const AREA = /^((?:[^:`]|`[^`]*`)+):(?=\s|[A-Z`]|$)(.*)$/;

// Capitalizes a first word written all in lowercase, and leaves `iOS`, a number or a quote as they are
function capitalizeFirstWord(text) {
  return text.replace(/^[a-z]+(?![A-Za-z])/, (word) => word[0].toUpperCase() + word.slice(1));
}

function stripFixMarkers(text) {
  let rest = text;
  for (let marker = FIX_MARKER_PREFIX.exec(rest); marker; marker = FIX_MARKER_PREFIX.exec(rest)) {
    rest = rest.slice(marker[0].length).trimStart();
  }

  return rest;
}

// Corrects what the rules can correct without a person: spacing, fix markers, capitals, a listed past
// form and trailing punctuation. Words are neither reordered nor guessed, so a missing area and
// a Conventional Commits prefix stay, and the title still fails on them.
export function fixTitle(title) {
  if (GENERATED_TITLES.some((pattern) => pattern.test(title))) return title;

  let rest = title.replace(/\s+/g, ' ').trim();
  const tags = [];
  for (let match = /^\[([^[\]]+)\]/.exec(rest); match; match = /^\[([^[\]]+)\]/.exec(rest)) {
    const tag = match[1].trim() || match[1];
    if (!FIX_MARKERS.has(tag.toLowerCase())) tags.push(tag);
    rest = rest.slice(match[0].length).trimStart();
  }

  const withTags = (text) => [...tags.map((tag) => `[${tag}]`), text].filter(Boolean).join(' ');

  if (CONVENTIONAL_PREFIX.test(rest)) return withTags(rest);

  rest = stripFixMarkers(rest.replace(/[.;\s]+$/, ''));

  let area = '';
  let description = rest;
  const areaMatch = AREA.exec(rest);
  if (areaMatch) {
    const segments = areaMatch[1].split('/');
    const kept = segments.filter((segment) => !FIX_MARKERS.has(segment.trim().toLowerCase()));
    area = capitalizeFirstWord(kept.length === segments.length ? areaMatch[1] : kept.join('/').trim());
    description = areaMatch[2].trimStart();
  }

  const tasks = stripFixMarkers(description)
    .split(TASK_SEPARATOR)
    .map((task) => capitalizeFirstWord(task.trim()))
    .filter(Boolean);
  if (tasks.length) {
    tasks[0] = tasks[0].replace(/^[A-Za-z]+/, (word) => IMPERATIVE_BY_PAST_TENSE.get(word) ?? word);
  }

  description = tasks.join('; ');
  return withTags(area ? `${area}: ${description}`.trimEnd() : description);
}

export function formatTitleReport(title, problems) {
  return [
    `PR title ${JSON.stringify(title)} breaks the commit format in CODESTYLE.md ("Commit Messages"):`,
    ...problems.map((problem) => `- ${RULES[problem]}`),
    `Expected: ${EXPECTED_SHAPE}`,
    `For example: ${EXAMPLE}`,
  ].join('\n');
}
