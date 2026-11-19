import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

// Turns the JSON report of a Web E2E job into the Markdown of its GitHub step summary:
// failed and skipped cases as full tables, flaky ones next, passed ones folded
//
//   node dev/webE2eSummary.mjs results.json --project mobile-chromium [--no-reasons] [--source-url <url>]

const ANSI_PATTERN = /\x1b\[[0-9;]*m/g;
// Lines of a Playwright error that name the element it waited for
const LOCATOR_LINE_PATTERN = /^\s*(Locator:|- waiting for)/;
const MAX_REASON_LENGTH = 200;
const NO_ERROR_MESSAGE = 'No error message';
const HIDDEN_REASON = 'Hidden in a wallet job';
const NOT_RUN_REASON = 'Not run: a setup it needs failed or the run stopped';
const SETUP_AREA = 'setup';

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      project: { type: 'string' },
      'no-reasons': { type: 'boolean', default: false },
      'source-url': { type: 'string' },
    },
  });
  console.log(buildJobSummary(readReport(positionals[0]), {
    project: values.project,
    noReasons: values['no-reasons'],
    sourceUrl: values['source-url'],
  }));
}

export function buildJobSummary(report, { project, noReasons = false, sourceUrl }) {
  if (!report) {
    return `### 🔴 ${project}: no results\n\nThe job stopped before the cases finished, see its log.\n`;
  }

  const cases = collectCases(report, noReasons);
  const { expected, unexpected, flaky, skipped, duration } = report.stats;
  const runErrors = report.errors ?? [];
  const icon = unexpected || runErrors.length ? '🔴' : flaky ? '🟡' : '🟢';
  const counts = [
    `${unexpected} failed`,
    `${flaky} flaky`,
    `${skipped} skipped`,
    `${expected} passed`,
    ...(runErrors.length ? [`${runErrors.length} run errors`] : []),
  ];
  const formatCase = (item) => formatCaseCell(item, sourceUrl);
  const formatReason = (reason) => (noReasons ? HIDDEN_REASON : escapeCell(reason));
  const filterByStatus = (status) => cases.filter((item) => item.status === status);
  const lines = [`### ${icon} ${project}: ${counts.join(', ')} · ${formatDuration(duration)}`, ''];

  if (runErrors.length) {
    lines.push('**Run errors**', '');
    runErrors.forEach((error) => lines.push(`- ${formatReason(summarizeError(error))}`));
    lines.push('');
  }
  lines.push(...buildTable('🔴 Failed', filterByStatus('unexpected'), ['Area', 'Case', 'Reason'],
    (item) => [item.area, formatCase(item), formatReason(item.error)]));
  lines.push(...buildTable('⚪ Skipped', filterByStatus('skipped'), ['Area', 'Case', 'Reason'],
    (item) => [item.area, formatCase(item), escapeCell(item.skipReason)]));
  lines.push(...buildTable('🟡 Flaky, passed on a retry', filterByStatus('flaky'), ['Area', 'Case', 'First failure'],
    (item) => [item.area, formatCase(item), formatReason(item.firstError)]));

  const passed = filterByStatus('expected');
  if (passed.length) {
    lines.push(`<details><summary>🟢 Passed: ${passed.length}</summary>`, '');
    lines.push(...buildTable(undefined, passed, ['Area', 'Case', 'Time'],
      (item) => [item.area, formatCase(item), formatDuration(item.duration)]));
    lines.push('</details>', '');
  }

  return lines.join('\n');
}

function collectCases(report, noReasons) {
  const cases = [];
  const visit = (suite) => {
    suite.specs?.forEach((spec) => spec.tests.forEach((test) => {
      const results = test.results ?? [];
      const last = results.at(-1);
      cases.push({
        title: spec.title,
        file: spec.file,
        line: spec.line,
        area: spec.file.includes('/') ? spec.file.split('/')[0] : SETUP_AREA,
        status: test.status,
        duration: results.reduce((total, result) => total + result.duration, 0),
        error: summarizeLastError(last?.errors),
        firstError: summarizeLastError(results[0]?.errors),
        skipReason: describeSkip(test, last, noReasons),
      });
    }));
    suite.suites?.forEach(visit);
  };
  report.suites.forEach(visit);

  return cases.sort((a, b) => a.area.localeCompare(b.area) || a.title.localeCompare(b.title));
}

// A wallet job keeps only the kind of a skip, as its description may quote a page
function describeSkip(test, lastResult, noReasons) {
  if (lastResult?.status === 'interrupted') return 'Interrupted';
  if (!lastResult) return NOT_RUN_REASON;
  const annotation = [...(test.annotations ?? []), ...(lastResult.annotations ?? [])]
    .find(({ type }) => type === 'skip' || type === 'fixme');
  if (!annotation) return 'Skipped';

  const kind = annotation.type === 'fixme' ? 'Fixme' : 'Skipped';

  return noReasons || !annotation.description ? kind : `${kind}: ${annotation.description}`;
}

function summarizeLastError(errors) {
  return errors?.length ? summarizeError(errors.at(-1)) : NO_ERROR_MESSAGE;
}

// The first line says what failed and the locator line says where, the rest is a call log and a code frame
function summarizeError(error) {
  const lines = (error.message ?? '').replace(ANSI_PATTERN, '').split('\n');
  const headline = lines.find((line) => line.trim())?.trim().replace(/^Error: /, '') ?? NO_ERROR_MESSAGE;
  const locator = lines.find((line) => LOCATOR_LINE_PATTERN.test(line))?.trim();
  const text = [headline, locator].filter(Boolean).join(' · ');

  return text.length > MAX_REASON_LENGTH ? `${text.slice(0, MAX_REASON_LENGTH - 1)}…` : text;
}

function buildTable(title, items, headers, toCells) {
  if (!items.length) return [];

  return [
    ...(title ? [`**${title}: ${items.length}**`, ''] : []),
    `| ${headers.join(' | ')} |`,
    `|${headers.map(() => '---').join('|')}|`,
    ...items.map((item) => `| ${toCells(item).join(' | ')} |`),
    '',
  ];
}

function formatCaseCell({ title, file, line }, sourceUrl) {
  const text = escapeCell(title);

  return sourceUrl ? `[${text.replace(/[[\]]/g, '\\$&')}](${sourceUrl}/${file}#L${line})` : text;
}

function escapeCell(text) {
  return text.replace(/\s+/g, ' ').replace(/\\/g, '\\\\').replace(/\|/g, '\\|').replace(/</g, '&lt;');
}

function formatDuration(milliseconds) {
  const seconds = Math.round(milliseconds / 1000);
  if (seconds < 60) return `${seconds}s`;

  return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, '0')}s`;
}

// A job killed mid-write leaves a truncated file, which reads as no results
function readReport(file) {
  try {
    return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : undefined;
  } catch {
    return undefined;
  }
}
