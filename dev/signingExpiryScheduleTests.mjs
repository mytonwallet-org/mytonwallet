import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import yaml from 'js-yaml';

// The weekly signing check promises a month of notice, and what it gives is its threshold minus
// however long passes between two runs: the run that still sees the threshold left stays silent, and
// the warning waits for the next one. The threshold and the cron are therefore one number written in
// two places, and a threshold read on its own says nothing about the notice it delivers.
//
// So the threshold is checked against the schedule rather than against itself. An expectation of the
// literal 45 would go red on every edit and prove nothing; deriving it from the cron leaves moving
// one of the two without the other as the only way to go red.
const PROJECT_ROOT = fileURLToPath(new URL('../', import.meta.url));
const CHECK_WORKFLOW = '.github/workflows/ios-signing-expiry.yml';
const BACKSTOP_WORKFLOW = '.github/workflows/ios-signing-expiry-backstop.yml';

// The promise, and the headroom it needs on a schedule that is allowed to skip. Editing these is
// editing what the check is for, which is why they are here in full sight rather than folded into
// an expected number.
const NOTICE_DAYS = 30;
const DROPPED_TICKS = 2;
const SLACK_DAYS = 1;

// The Gregorian calendar repeats exactly every 400 years, and those 146097 days are also a whole
// number of weeks, so every field a cron can name - minute, hour, day of month, month, weekday -
// lands back on the same footing. That makes one such span a true period rather than a long sample,
// which is what lets the measurement below have no window length to be wrong about. A fixed span at
// a fixed start also keeps the answer from depending on when the test happens to run, and cron in
// Actions is UTC throughout, so no offset ever moves inside it.
const CYCLE_START = Date.UTC(2000, 0, 1);
const CYCLE_DAYS = 146_097;
const DAY_MS = 86_400_000;

const FIELDS = [
  { name: 'minute', min: 0, max: 59 },
  { name: 'hour', min: 0, max: 23 },
  { name: 'day of month', min: 1, max: 31 },
  { name: 'month', min: 1, max: 12 },
  { name: 'day of week', min: 0, max: 7 },
];

function loadWorkflow(relativePath) {
  const text = readFileSync(path.join(PROJECT_ROOT, relativePath), 'utf8');
  const doc = yaml.load(text);

  // `on` is a boolean in YAML 1.1, and a parser on that schema files the triggers under `true`
  // instead. js-yaml 4 defaults to the 1.2 core schema and keeps the string, so both spellings are
  // read rather than betting on which one arrived - the wrong bet here returns undefined, not an
  // error, and a schedule nobody found would pass this file silently.
  const triggers = doc.on ?? doc[true];
  assert.ok(triggers, `${relativePath}: no triggers found under \`on\``);

  // Every step's script, so that moving the constant to another step or job keeps this readable.
  // Reading the parsed scripts rather than the raw file also keeps prose elsewhere in the YAML from
  // ever standing in for the line that actually runs.
  const script = Object.values(doc.jobs ?? {})
    .flatMap((job) => (job.steps ?? []).map((step) => step.run))
    .filter(Boolean)
    .join('\n');
  assert.ok(script, `${relativePath}: no step scripts found`);

  return { triggers, script };
}

// Refuses what it cannot reason about instead of defaulting, because a plausible wrong interval
// here produces a plausible wrong threshold and nothing to notice it by.
function expandField(spec, field, cron) {
  const unsupported = `${cron}: cannot read the ${field.name} field ("${spec}") - teach this test the new shape`;
  const values = new Set();

  for (const part of spec.split(',')) {
    const [rangeText, stepText] = part.split('/');
    const step = stepText === undefined ? 1 : Number(stepText);
    assert.ok(Number.isInteger(step) && step > 0, unsupported);

    let from;
    let to;
    if (rangeText === '*') {
      [from, to] = [field.min, field.max];
    } else if (rangeText.includes('-')) {
      [from, to] = rangeText.split('-').map(Number);
    } else {
      from = Number(rangeText);
      to = stepText === undefined ? from : field.max;
    }

    assert.ok(Number.isInteger(from) && Number.isInteger(to), unsupported);
    assert.ok(from >= field.min && to <= field.max && from <= to, unsupported);

    // Cron spells Sunday both 0 and 7, and a set holding 7 matches nothing a date can report.
    for (let value = from; value <= to; value += step) {
      values.add(field.name === 'day of week' ? value % 7 : value);
    }
  }

  return values;
}

function parseCron(cron) {
  const specs = String(cron).trim().split(/\s+/);
  assert.equal(specs.length, FIELDS.length, `${cron}: expected ${FIELDS.length} cron fields`);

  return {
    fields: FIELDS.map((field, index) => expandField(specs[index], field, cron)),
    // Day-of-month and day-of-week are OR'd when both are restricted, and AND'd with the rest.
    restricted: FIELDS.map((_, index) => specs[index] !== '*'),
  };
}

function fallsOnDay({ fields, restricted }, date) {
  const [, , dayOfMonth, month, dayOfWeek] = fields;
  if (!month.has(date.getUTCMonth() + 1)) return false;

  const dayOfMonthHit = dayOfMonth.has(date.getUTCDate());
  const dayOfWeekHit = dayOfWeek.has(date.getUTCDay());
  if (restricted[2] && restricted[4]) return dayOfMonthHit || dayOfWeekHit;
  if (restricted[2]) return dayOfMonthHit;
  if (restricted[4]) return dayOfWeekHit;
  return true;
}

// Walks days rather than minutes, and only the hours and minutes the cron actually names, which is
// what keeps a four-century span to a hundred and fifty thousand steps.
function firingsOverCycle(schedule) {
  const end = CYCLE_START + CYCLE_DAYS * DAY_MS;
  const fires = new Set();

  for (let day = CYCLE_START; day < end; day += DAY_MS) {
    const date = new Date(day);
    for (const cron of schedule) {
      if (!fallsOnDay(cron, date)) continue;
      for (const hour of cron.fields[1]) {
        for (const minute of cron.fields[0]) fires.add(day + hour * 3_600_000 + minute * 60_000);
      }
    }
  }

  return [...fires].sort((first, second) => first - second);
}

// The longest a healthy schedule can stay quiet, measured by running it rather than by reading the
// fields and deciding what they mean. "Two ticks of the cron" is this number, whatever shape the
// cron grows into, and several schedule entries are one schedule here just as they are to Actions.
//
// The period is closed into a ring, so the gap from the last firing of the cycle to the first firing
// of the next is measured like any other. Left open, that one gap is the only one nobody sees, and a
// calendar schedule can hide its longest silence there: a cron on February 1 and March 1 shows a
// month between them and says nothing about the eleven months back round to February. Sampling
// answers this wrong rather than loudly - two spans agreeing on a maximum is not the same as having
// found it, and a February 29 cron reads four years in any span that misses a century that skips
// its leap day. A full period has no edge to fall off, so there is nothing left to agree about.
function longestQuietDays(crons) {
  const fires = firingsOverCycle(crons.map(parseCron));
  assert.ok(fires.length > 0, `a schedule that never fires (${crons.join(', ')}) has no interval to derive from`);

  let longest = fires[0] + CYCLE_DAYS * DAY_MS - fires[fires.length - 1];
  for (let index = 1; index < fires.length; index++) {
    longest = Math.max(longest, fires[index] - fires[index - 1]);
  }

  return longest / DAY_MS;
}

function soleAssignment(script, name, pattern, workflow) {
  const found = [...script.matchAll(new RegExp(`^[ \\t]*${name}[ \\t]*=[ \\t]*${pattern}[ \\t]*(?:#.*)?$`, 'gm'))];
  assert.equal(
    found.length,
    1,
    `${workflow}: expected exactly one \`${name} = ...\`, found ${found.length} - the last one is what Python runs`,
  );
  return found[0][1];
}

function scheduleOf(triggers, workflow) {
  const schedule = triggers.schedule ?? [];
  assert.ok(schedule.length > 0, `${workflow}: no \`schedule\` trigger`);
  return schedule.map((entry) => entry.cron);
}

const check = loadWorkflow(CHECK_WORKFLOW);
const backstop = loadWorkflow(BACKSTOP_WORKFLOW);
const quietDays = longestQuietDays(scheduleOf(check.triggers, CHECK_WORKFLOW));

test('the expiry threshold carries the notice its own schedule needs', () => {
  const threshold = Number(soleAssignment(check.script, 'THRESHOLD', '(\\d+)', CHECK_WORKFLOW));
  const expected = NOTICE_DAYS + DROPPED_TICKS * quietDays + SLACK_DAYS;

  assert.ok(
    Number.isInteger(expected),
    `a schedule quiet for ${quietDays} days at a time cannot be answered by a whole-day threshold`,
  );
  assert.equal(
    threshold,
    expected,
    `THRESHOLD in ${CHECK_WORKFLOW} is ${threshold}, but its cron goes quiet for up to ${quietDays} days at a time,`
      + ` which needs ${expected} (${NOTICE_DAYS} days of notice + ${DROPPED_TICKS} dropped runs + ${SLACK_DAYS} of`
      + ' slack). Move the threshold and the cron together, or say here what the promise now is.',
  );
});

test('the threshold is the number the check compares against', () => {
  // The name also appears in the run's own summary line, so a test that counts mentions stays green
  // when the comparison is rewritten to a literal. Pinning the predicate is what keeps the threshold
  // derived here from becoming decoration.
  const predicates = [...check.script.matchAll(/^[ \t]*expiring[ \t]*=[ \t]*\[(.+)\][ \t]*$/gm)];
  assert.equal(
    predicates.length,
    1,
    `${CHECK_WORKFLOW}: expected exactly one \`expiring = [...]\`, found ${predicates.length}`,
  );
  assert.match(
    predicates[0][1],
    /<[ \t]*THRESHOLD\b/,
    `the expiry predicate in ${CHECK_WORKFLOW} does not compare against THRESHOLD, so the threshold this file`
      + ' derives from the schedule decides nothing',
  );
});

test('the backstop stands in for a schedule that stopped rather than one that is merely quiet', () => {
  const maxAge = Number(soleAssignment(backstop.script, 'MAX_AGE_DAYS', '(\\d+)', BACKSTOP_WORKFLOW));

  assert.ok(
    maxAge > quietDays,
    `MAX_AGE_DAYS in ${BACKSTOP_WORKFLOW} is ${maxAge}, which a healthy schedule already exceeds by going quiet for`
      + ` ${quietDays} days, so the backstop would dispatch the check on every release instead of when it is overdue`,
  );
});

test('the backstop asks for the workflow that holds the check', () => {
  const named = soleAssignment(backstop.script, 'CHECK', '"([^"]+)"', BACKSTOP_WORKFLOW);

  assert.equal(
    named,
    path.basename(CHECK_WORKFLOW),
    `${BACKSTOP_WORKFLOW} dispatches "${named}", which is not the workflow holding the check`,
  );
});
