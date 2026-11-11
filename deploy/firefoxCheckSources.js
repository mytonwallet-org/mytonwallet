const { execFileSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

// AMO reviewers take library provenance from `SOURCE_CODE_REVIEW.md`, so the archive must not hold a file
// in `src/lib`, a hash or a `.wasm` binary that the document does not account for

const THIRD_PARTY_SECTION = 'Third-party code';
const BINARIES_SECTION = 'Compiled binaries';
const FIRST_PARTY_SECTION = 'First-party code';

const [archivePath] = process.argv.slice(2);

if (!archivePath) {
  throw new Error('Usage: node deploy/firefoxCheckSources.js <sources.tgz>');
}

const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'firefox-sources-'));

try {
  execFileSync('tar', ['-xzf', archivePath, '-C', workDir]);

  const errors = check(workDir);
  if (errors.length) {
    process.stderr.write(`${errors.join('\n')}\n`);
    process.exit(1);
  }

  process.stdout.write('The source archive matches SOURCE_CODE_REVIEW.md\n');
} finally {
  fs.rmSync(workDir, { recursive: true, force: true });
}

function check(root) {
  const docPath = path.join(root, 'SOURCE_CODE_REVIEW.md');
  if (!fs.existsSync(docPath)) {
    return ['SOURCE_CODE_REVIEW.md is missing from the archive root'];
  }

  const doc = fs.readFileSync(docPath, 'utf8');
  const errors = [];
  const hashedFiles = new Set();
  const vendoredDirs = new Set();
  const hashRows = listHashTableRows(doc);

  for (const section of [THIRD_PARTY_SECTION, BINARIES_SECTION]) {
    if (!hashRows.some((entry) => entry.section.startsWith(section))) {
      errors.push(`SOURCE_CODE_REVIEW.md has no table with a SHA-256 column in its "${section}" section`);
    }
  }

  for (const { section, row } of hashRows) {
    const match = row.match(/^\| `([^`]+)` \|.*\| `([0-9a-f]{64})` \|$/);
    if (!match) {
      errors.push(`SOURCE_CODE_REVIEW.md has a row without a file or a SHA-256: ${row}`);
      continue;
    }

    const [, file, expectedHash] = match;
    hashedFiles.add(file);
    if (section.startsWith(THIRD_PARTY_SECTION) && path.dirname(file) !== 'src/lib') {
      vendoredDirs.add(path.dirname(file));
    }

    const filePath = path.join(root, file);
    if (!fs.existsSync(filePath)) {
      errors.push(`${file} is listed with a hash but is missing from the archive`);
      continue;
    }

    const actualHash = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
    if (actualHash !== expectedHash) {
      errors.push(`${file} has SHA-256 ${actualHash}, while SOURCE_CODE_REVIEW.md states ${expectedHash}`);
    }
  }

  // A bare name only counts in the first-party list, so a mention in another section cannot vouch for a new library
  const firstPartyText = getSectionText(doc, FIRST_PARTY_SECTION);
  for (const entry of fs.readdirSync(path.join(root, 'src/lib'))) {
    if (
      !doc.includes(`\`src/lib/${entry}\``)
      && !doc.includes(`\`src/lib/${entry}/`)
      && !firstPartyText.includes(`\`${entry}\``)
    ) {
      errors.push(`src/lib/${entry} is not described in SOURCE_CODE_REVIEW.md`);
    }
  }

  for (const dir of vendoredDirs) {
    for (const file of listFiles(root, dir)) {
      if (!hashedFiles.has(file)) {
        errors.push(`${file} sits in a vendored library but SOURCE_CODE_REVIEW.md gives no release for it`);
      }
    }
  }

  for (const file of listFiles(root)) {
    if (file.endsWith('.wasm') && !hashedFiles.has(file)) {
      errors.push(`${file} is a compiled binary that SOURCE_CODE_REVIEW.md gives no source for`);
    }
  }

  return errors;
}

function getSectionText(doc, section) {
  const lines = doc.split('\n');
  const start = lines.findIndex((line) => line.startsWith(`## ${section}`));
  if (start === -1) return '';

  const end = lines.findIndex((line, index) => index > start && line.startsWith('## '));
  return lines.slice(start + 1, end === -1 ? undefined : end).join('\n');
}

// Rows of the tables that carry a SHA-256 column, with the `##` section each one stands in
function listHashTableRows(doc) {
  const rows = [];
  let section = '';
  let isHashTable = false;
  let previousLine = '';

  for (const line of doc.split('\n')) {
    if (line.startsWith('## ')) {
      section = line.slice(3);
    } else if (line.startsWith('|') && !previousLine.startsWith('|')) {
      isHashTable = line.includes('SHA-256');
    } else if (isHashTable && line.startsWith('|') && !/^\|[-|\s]+\|$/.test(line)) {
      rows.push({ section, row: line });
    }
    previousLine = line;
  }

  return rows;
}

function listFiles(root, dir = '') {
  return fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap((entry) => {
    const relativePath = dir ? `${dir}/${entry.name}` : entry.name;
    return entry.isDirectory() ? listFiles(root, relativePath) : [relativePath];
  });
}
