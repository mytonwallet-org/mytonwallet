import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Agent V2 reaches the app only through these dynamic imports
const LAZY_ENTRIES = [
  'src/components/agentV2/AgentV2Classic.tsx',
  'src/components/agentV2/AgentV2HostContextBridge.tsx',
];
const AGENT_V2_RUNTIME_PATTERNS = [
  '/src/api/agentV2/',
  '/src/components/agentV2/',
  '/src/components/agent/hooks/agentV2',
  '/src/components/agent/hooks/useAgentV2Messages.ts',
];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  checkAgentV2BundleBoundary();
}

// Reads the `bundle-manifest.json` a stats build writes, see `plugins/bundleManifest.ts`
export function getAgentV2BundleBoundaryFailures(manifest) {
  const failures = [];
  const chunkByFileName = new Map(manifest.chunks.map((chunk) => [chunk.fileName, chunk]));
  const mainChunk = manifest.chunks.find((chunk) => chunk.isEntry && chunk.name === 'main');
  if (!mainChunk) {
    return ['Missing the main entry chunk'];
  }

  const initialFileNames = collectStaticImports(mainChunk, chunkByFileName);
  const initialAgentV2Modules = [...initialFileNames].flatMap((fileName) => chunkByFileName.get(fileName).modules
    .filter((modulePath) => AGENT_V2_RUNTIME_PATTERNS.some((pattern) => `/${modulePath}`.includes(pattern)))
    .map((modulePath) => `  /${modulePath} [${fileName}]`));

  if (initialAgentV2Modules.length) {
    failures.push(`Agent V2 runtime is present in the initial main graph:\n${initialAgentV2Modules.join('\n')}`);
  }

  for (const lazyEntry of LAZY_ENTRIES) {
    const chunk = manifest.chunks.find(({ facadeModuleId }) => facadeModuleId === lazyEntry);
    if (!chunk) {
      failures.push(`Missing the lazy chunk of ${lazyEntry}`);
    } else if (!chunk.isDynamicEntry || initialFileNames.has(chunk.fileName)) {
      failures.push(`${lazyEntry} must load lazily`);
    }
  }

  return failures;
}

function checkAgentV2BundleBoundary() {
  const manifestPath = readOption('--manifest');
  if (!manifestPath) throw new Error('Pass --manifest <bundle-manifest.json>');

  const manifest = JSON.parse(fs.readFileSync(path.resolve(PROJECT_ROOT, manifestPath), 'utf8'));
  const failures = getAgentV2BundleBoundaryFailures(manifest);
  if (failures.length) {
    throw new Error(`Agent V2 bundle boundary check failed:\n- ${failures.join('\n- ')}`);
  }

  console.log('Agent V2 bundle boundary check passed');
}

function readOption(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

// The chunk and every chunk it imports statically: what the browser loads before the entry runs
function collectStaticImports(chunk, chunkByFileName) {
  const fileNames = new Set();
  const queue = [chunk.fileName];
  while (queue.length) {
    const fileName = queue.shift();
    if (fileNames.has(fileName) || !chunkByFileName.has(fileName)) continue;
    fileNames.add(fileName);
    queue.push(...chunkByFileName.get(fileName).imports);
  }
  return fileNames;
}
