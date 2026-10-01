import assert from 'node:assert/strict';
import test from 'node:test';

import { getAgentV2BundleBoundaryFailures } from './checkAgentV2BundleBoundary.mjs';

test('accepts Agent V2 runtime in lazy chunks', () => {
  assert.deepEqual(getAgentV2BundleBoundaryFailures(createManifest()), []);
});

test('rejects Agent V2 runtime in the main graph and an initial Agent V2 chunk', () => {
  const manifest = createManifest();
  findChunk(manifest, 'shared.js').modules.push('src/api/agentV2/runtime.ts');
  findChunk(manifest, 'main.js').imports.push('AgentV2HostContextBridge.js');

  assert.deepEqual(getAgentV2BundleBoundaryFailures(manifest), [
    'Agent V2 runtime is present in the initial main graph:\n'
      + '  /src/api/agentV2/runtime.ts [shared.js]\n'
      + '  /src/components/agentV2/AgentV2HostContextBridge.tsx [AgentV2HostContextBridge.js]',
    'src/components/agentV2/AgentV2HostContextBridge.tsx must load lazily',
  ]);
});

test('rejects a missing Agent V2 lazy chunk', () => {
  const manifest = createManifest();
  manifest.chunks = manifest.chunks.filter(({ fileName }) => fileName !== 'AgentV2Classic.js');

  assert.deepEqual(getAgentV2BundleBoundaryFailures(manifest), [
    'Missing the lazy chunk of src/components/agentV2/AgentV2Classic.tsx',
  ]);
});

test('rejects the host context bridge bundled into the main chunk', () => {
  const manifest = createManifest();
  manifest.chunks = manifest.chunks.filter(({ fileName }) => fileName !== 'AgentV2HostContextBridge.js');
  findChunk(manifest, 'main.js').modules.push('src/components/agentV2/AgentV2HostContextBridge.tsx');

  assert.deepEqual(getAgentV2BundleBoundaryFailures(manifest), [
    'Agent V2 runtime is present in the initial main graph:\n  /src/components/agentV2/AgentV2HostContextBridge.tsx [main.js]',
    'Missing the lazy chunk of src/components/agentV2/AgentV2HostContextBridge.tsx',
  ]);
});

test('rejects a build without the main entry', () => {
  const manifest = createManifest();
  findChunk(manifest, 'main.js').isEntry = false;

  assert.deepEqual(getAgentV2BundleBoundaryFailures(manifest), ['Missing the main entry chunk']);
});

function findChunk(manifest, fileName) {
  return manifest.chunks.find((chunk) => chunk.fileName === fileName);
}

function createManifest() {
  return {
    chunks: [{
      fileName: 'main.js',
      name: 'main',
      isEntry: true,
      isDynamicEntry: false,
      facadeModuleId: 'src/index.html',
      imports: ['shared.js'],
      dynamicImports: ['AgentV2Classic.js', 'AgentV2HostContextBridge.js'],
      modules: ['src/index.tsx'],
    }, {
      fileName: 'shared.js',
      name: 'shared',
      isEntry: false,
      isDynamicEntry: false,
      imports: [],
      dynamicImports: [],
      modules: ['src/lib/teact/teact.ts'],
    }, {
      fileName: 'AgentV2Classic.js',
      name: 'AgentV2Classic',
      isEntry: false,
      isDynamicEntry: true,
      facadeModuleId: 'src/components/agentV2/AgentV2Classic.tsx',
      imports: ['shared.js'],
      dynamicImports: [],
      modules: ['src/components/agentV2/AgentV2Classic.tsx', 'src/api/agentV2/runtime.ts'],
    }, {
      fileName: 'AgentV2HostContextBridge.js',
      name: 'AgentV2HostContextBridge',
      isEntry: false,
      isDynamicEntry: true,
      facadeModuleId: 'src/components/agentV2/AgentV2HostContextBridge.tsx',
      imports: ['shared.js'],
      dynamicImports: [],
      modules: ['src/components/agentV2/AgentV2HostContextBridge.tsx'],
    }],
  };
}
