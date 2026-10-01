// Posts the bundle size diff with master as a PR comment, updating the previous one in place. Runs from
// `.github/workflows/bundle-stats.yml`. Run it locally to print the comment:
//   node dev/createBundleStatsComment.mjs [current-stats.json] [baseline-stats.json]

import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const COMMENT_MARKER = '<!-- mytonwallet-bundle-stats-comment -->';
const COMMENT_TITLE = '**Bundle stats diff with master**';
const DEFAULT_CURRENT_STATS_PATH = 'dist/bundle-stats/baseline.json';
const DEFAULT_BASELINE_STATS_PATH = 'reference-bundle-stats/baseline.json';
const REGRESSION_WARNING_PERCENT = 1.5;
const BYTES_PER_KB = 1000;
const BYTES_PER_MB = BYTES_PER_KB * 1000;
const STATUS_GOOD = '🟢';
const STATUS_WARN = '🔴';
const STATUS_NEUTRAL = '⚪️';

const MAIN_ENTRY = { key: 'main', label: '🏠 Main' };
// Worker bundles follow the `[name].[hash].js` pattern of `plugins/viteBase.ts`
const WORKER_ENTRIES = [
  { key: 'api-worker', label: '⚙️ API worker', pattern: /^provider\.[\w-]{8}\.js$/ },
  { key: 'media-worker', label: '🎞️ Media worker', pattern: /^index\.worker\.[\w-]{8}\.js$/ },
];
const ENTRY_ORDER = [MAIN_ENTRY.key, ...WORKER_ENTRIES.map(({ key }) => key)];
const FILE_TYPES = [
  { key: 'js', label: '🟨 JS', extensions: ['.js', '.mjs', '.cjs'] },
  { key: 'css', label: '🎨 CSS', extensions: ['.css'] },
  { key: 'wasm', label: '⚙️ WASM', extensions: ['.wasm'] },
  { key: 'other', label: '📄 Other', extensions: [] },
];

export default async function createBundleStatsComment({ github, context, core }) {
  const body = createCommentBody({
    baselineStatsPath: process.env.BASELINE_BUNDLE_STATS_PATH || DEFAULT_BASELINE_STATS_PATH,
    currentStatsPath: process.env.CURRENT_BUNDLE_STATS_PATH || DEFAULT_CURRENT_STATS_PATH,
    reportUrl: process.env.REPORT_URL || '',
  });

  await upsertComment({ github, context, core, body });
}

export async function createBundleStatsPendingComment({ github, context, core }) {
  await upsertComment({
    github,
    context,
    core,
    body: [
      COMMENT_MARKER,
      COMMENT_TITLE,
      '',
      '> [!NOTE]',
      '> Bundle size measuring is in progress.',
      '> This comment will be updated with the latest results when the build finishes.',
    ].join('\n'),
  });
}

export function createCommentBody({ baselineStatsPath, currentStatsPath, reportUrl }) {
  const currentStats = readStats(currentStatsPath);
  if (!currentStats) {
    return [COMMENT_MARKER, COMMENT_TITLE, '', `Current stats file was not found at \`${currentStatsPath}\`.`].join('\n');
  }

  const current = analyzeStats(currentStats);
  const baselineStats = readStats(baselineStatsPath);
  if (!baselineStats) {
    return [
      COMMENT_MARKER,
      COMMENT_TITLE,
      '',
      `Master baseline stats were not found at \`${baselineStatsPath}\`.`,
      `Current total bundle size: ${formatSize(current.totalSize)}`,
      '',
      '**📦 File type**',
      ...[...current.fileTypes.values()].map(renderSizeLine),
      '',
      '**🚪 Entry point**',
      ...[...current.entries.values()].sort(compareEntries).map(renderSizeLine),
    ].join('\n');
  }

  const baseline = analyzeStats(baselineStats);
  const lines = [
    COMMENT_MARKER,
    COMMENT_TITLE,
    '',
    renderDiffLine(createDiffRow('📊 Total bundle', baseline.totalSize, current.totalSize)),
  ];
  addDiffSection(lines, '**📦 File type**', FILE_TYPES.map(({ key, label }) => (
    createDiffRow(label, baseline.fileTypes.get(key)?.size, current.fileTypes.get(key)?.size)
  )));
  addDiffSection(lines, '**🚪 Entry point**', ENTRY_ORDER.map((key) => createDiffRow(
    (current.entries.get(key) ?? baseline.entries.get(key)).label,
    baseline.entries.get(key)?.size,
    current.entries.get(key)?.size,
  )));
  if (reportUrl) {
    lines.push('', `Detailed comparison report: [open HTML artifact](${reportUrl})`);
  }

  return lines.join('\n');
}

function readStats(filePath) {
  return existsSync(filePath) ? JSON.parse(readFileSync(filePath, 'utf8')) : undefined;
}

// The main entry counts the files the browser loads upfront: the entry chunk, its static imports and CSS
function analyzeStats(stats) {
  const entries = new Map([
    [MAIN_ENTRY.key, { ...MAIN_ENTRY, size: 0 }],
    ...WORKER_ENTRIES.map(({ key, label }) => [key, { key, label, size: 0 }]),
  ]);
  const fileTypes = new Map(FILE_TYPES.map(({ key, label }) => [key, { key, label, size: 0 }]));
  const initialFiles = new Set((stats.chunks ?? [])
    .filter(({ entry, initial }) => entry || initial)
    .flatMap(({ files = [] }) => files));

  let totalSize = 0;
  for (const { name, size } of stats.assets ?? []) {
    if (name.endsWith('.map') || name.startsWith('bundle-stats/')) continue;

    totalSize += size;
    const fileType = FILE_TYPES.find(({ extensions }) => extensions.some((extension) => name.endsWith(extension)))
      ?? FILE_TYPES[FILE_TYPES.length - 1];
    fileTypes.get(fileType.key).size += size;

    const workerEntry = WORKER_ENTRIES.find(({ pattern }) => pattern.test(name));
    if (workerEntry) {
      entries.get(workerEntry.key).size += size;
    } else if (initialFiles.has(name)) {
      entries.get(MAIN_ENTRY.key).size += size;
    }
  }

  return { entries, fileTypes, totalSize };
}

function createDiffRow(label, before = 0, after = 0) {
  const diff = after - before;
  const percent = before ? (diff / before) * 100 : undefined;
  const status = diff < 0 ? STATUS_GOOD
    : (percent === undefined ? diff > 0 : percent > REGRESSION_WARNING_PERCENT) ? STATUS_WARN
      : STATUS_NEUTRAL;
  const sign = diff > 0 ? '+' : diff < 0 ? '-' : '';
  const percentText = percent === undefined ? (diff ? 'new' : '0%') : `${percent > 0 ? '+' : ''}${formatNumber(percent)}%`;

  return { label, after, diff, status, diffText: `${sign}${formatSize(diff)}`, percentText };
}

function addDiffSection(lines, title, rows) {
  const changedRows = rows.filter(({ diff }) => diff !== 0);
  if (changedRows.length) {
    lines.push('', title, ...changedRows.map(renderDiffLine));
  }
}

function compareEntries(a, b) {
  return ENTRY_ORDER.indexOf(a.key) - ENTRY_ORDER.indexOf(b.key);
}

function renderDiffLine({ label, after, status, diffText, percentText }) {
  return `${label} (${formatSize(after)}): ${status} ${diffText} (${percentText})`;
}

function renderSizeLine({ label, size }) {
  return `${label} (${formatSize(size)})`;
}

function formatSize(size) {
  const absoluteSize = Math.abs(size);
  if (absoluteSize >= BYTES_PER_MB) return `${formatNumber(absoluteSize / BYTES_PER_MB)}MB`;
  if (absoluteSize >= BYTES_PER_KB) return `${formatNumber(absoluteSize / BYTES_PER_KB)}KB`;
  return `${absoluteSize}B`;
}

function formatNumber(value) {
  return value.toLocaleString('en-US', { maximumFractionDigits: 2, minimumFractionDigits: 0 });
}

async function upsertComment({ github, context, core, body }) {
  const { owner, repo } = context.repo;
  const issueNumber = Number(process.env.PR_NUMBER || context.issue.number);
  if (!issueNumber) {
    throw new Error('Cannot create bundle stats comment without a PR number');
  }

  const { data: comments } = await github.rest.issues.listComments({
    owner, repo, issue_number: issueNumber, per_page: 100,
  });
  const previousComment = comments.find(({ body: commentBody = '' }) => commentBody.includes(COMMENT_MARKER));

  if (previousComment) {
    await github.rest.issues.updateComment({ owner, repo, comment_id: previousComment.id, body });
    core.info(`Updated bundle stats comment ${previousComment.id}.`);
    return;
  }

  const { data: comment } = await github.rest.issues.createComment({ owner, repo, issue_number: issueNumber, body });
  core.info(`Created bundle stats comment ${comment.id}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , currentStatsPath = DEFAULT_CURRENT_STATS_PATH, baselineStatsPath = DEFAULT_BASELINE_STATS_PATH] = process.argv;
  console.log(createCommentBody({ baselineStatsPath, currentStatsPath, reportUrl: process.env.REPORT_URL || '' }));
}
