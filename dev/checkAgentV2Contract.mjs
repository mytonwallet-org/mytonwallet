import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const generatedDirectory = path.join(repositoryRoot, 'src/api/agentV2/generated');
const fixtureDirectory = path.join(repositoryRoot, 'tests/fixtures/agentV2');
const manifestPath = path.join(generatedDirectory, 'manifest.json');
const inventoryPath = path.join(fixtureDirectory, 'public-contract-fixture-inventory.v1.json');
const filterCatalogPath = path.join(generatedDirectory, 'wallet-filter-fields.v1.json');
const publicTypesPath = path.join(generatedDirectory, 'public.ts');
const publicConstantsPath = path.join(generatedDirectory, 'constants.ts');
const staleArtifactPaths = [
  path.join(generatedDirectory, 'agent-v2-public.schema.json'),
  path.join(generatedDirectory, 'fixtures'),
];

const manifest = readJson(manifestPath);
if (manifest.schemaVersion !== 5 || manifest.protocolVersion !== 3) {
  throw new Error('Unsupported Agent V2 client contract manifest');
}
for (const filename of staleArtifactPaths) {
  if (fs.existsSync(filename)) throw new Error(`Stale Agent V2 artifact: ${path.relative(repositoryRoot, filename)}`);
}

assertDigest(inventoryPath, manifest.fixtureInventorySha256);
assertDigest(filterCatalogPath, manifest.walletFilterCatalogSha256);
assertDigest(publicTypesPath, manifest.publicTypesSha256);
assertDigest(publicConstantsPath, manifest.publicConstantsSha256);

const inventory = readJson(inventoryPath);
if (
  inventory.schemaVersion !== 1
  || inventory.inventoryVersion !== 'agent-v2-public-contract-fixture-inventory-v1'
  || !Array.isArray(inventory.files)
) {
  throw new Error('Unsupported Agent V2 fixture inventory');
}
const inventoryFiles = [...inventory.files].sort();
const digestedFixtureFiles = Object.keys(manifest.fixtureSha256ByName ?? {}).sort();
const actualFixtureFiles = fs.readdirSync(fixtureDirectory)
  .filter((filename) => filename.endsWith('.json'))
  .sort();
if (new Set(inventory.files).size !== inventory.files.length) {
  throw new Error('Duplicate Agent V2 fixture inventory entry');
}
if (JSON.stringify(inventory.files) !== JSON.stringify(inventoryFiles)) {
  throw new Error('Agent V2 fixture inventory entries are not sorted');
}
if (inventory.files.filter((filename) => filename === path.basename(inventoryPath)).length !== 1) {
  throw new Error('Agent V2 fixture inventory must include itself exactly once');
}
if (JSON.stringify(inventoryFiles) !== JSON.stringify(digestedFixtureFiles)) {
  throw new Error('Agent V2 fixture digest map does not match the public inventory');
}
if (JSON.stringify(inventoryFiles) !== JSON.stringify(actualFixtureFiles)) {
  throw new Error('Agent V2 fixture directory does not match the public inventory');
}
for (const filename of inventory.files) {
  if (path.basename(filename) !== filename) throw new Error(`Unsafe Agent V2 fixture path: ${filename}`);
  const fixturePath = path.join(fixtureDirectory, filename);
  if (!fs.existsSync(fixturePath)) throw new Error(`Missing Agent V2 fixture: ${filename}`);
  const expectedDigest = manifest.fixtureSha256ByName[filename];
  if (!/^[0-9a-f]{64}$/u.test(expectedDigest)) {
    throw new Error(`Invalid Agent V2 fixture digest: ${filename}`);
  }
  assertDigest(fixturePath, expectedDigest);
  readJson(fixturePath);
}

process.stdout.write(`Agent V2 client contract of protocol ${manifest.protocolVersion} is internally consistent.\n`);

function assertDigest(filename, expected) {
  const actual = createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
  if (actual !== expected) throw new Error(`Agent V2 contract digest mismatch: ${path.relative(repositoryRoot, filename)}`);
}

function readJson(filename) {
  return JSON.parse(fs.readFileSync(filename, 'utf8'));
}
