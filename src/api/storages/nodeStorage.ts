import type { Storage } from './types';

type NodeFileStorageModule = {
  createNodeFileStorage(config: { path?: string; profile?: string }): Storage;
};

const isNode = typeof process === 'object' && Boolean(process.versions?.node);
const DEFAULT_NODE_STORAGE_FILENAME = '.mywallet/storage.json';

export const nodeStorage = isNode
  ? loadNodeFileStorageModule().createNodeFileStorage({ path: resolveNodeStorageFilename() })
  : undefined;

function resolveNodeStorageFilename() {
  const nodeStorageFilenameFromEnvironment = process.env.STORAGE_FILENAME?.trim();

  return nodeStorageFilenameFromEnvironment || DEFAULT_NODE_STORAGE_FILENAME;
}

function loadNodeFileStorageModule() {
  const nodeRequire = getNodeRequire();

  return nodeRequire('./nodeFile') as NodeFileStorageModule;
}

function getNodeRequire() {
  try {
    const indirectRequire = globalThis.eval?.('require');

    if (typeof indirectRequire === 'function') {
      return indirectRequire as NodeJS.Require;
    }
  } catch (_err) {
    // Ignore environments where indirect require is unavailable
  }

  if (typeof require === 'function') {
    return require;
  }

  if (typeof module !== 'undefined' && typeof module.require === 'function') {
    return module.require.bind(module) as NodeJS.Require;
  }

  throw new Error('Node-compatible require is unavailable for node-file storage');
}
