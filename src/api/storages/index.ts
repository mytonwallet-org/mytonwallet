import type { ApiStorageConfig, NodeFileStorageConfig, Storage, StorageKey } from './types';
import { StorageType } from './types';

import { IS_AIR_APP, IS_EXTENSION } from '../../config';
import airStorage from './airStorage';
import extensionStorage from './extension';
import idb from './idb';
import localStorage from './localStorage';

const storages = {
  [StorageType.IndexedDb]: idb,
  [StorageType.LocalStorage]: localStorage,
  [StorageType.ExtensionLocal]: extensionStorage,
  [StorageType.AirStorage]: airStorage,
} satisfies Partial<Record<StorageType, Storage>>;

// These singletons live on globalThis so that duplicated bundle chunks share the same state.
// Without this, split chunks each get their own module-local copies and storage context is lost.
const STORAGE_GLOBALS_KEY = '__mtwStorageGlobals';

type NodeFileStorageFactory = (config: NodeFileStorageConfig) => Storage;

type StorageGlobals = {
  storageContext?: StorageContext | false;
  legacyStorage?: Storage;
  nodeFileStorageFactory?: NodeFileStorageFactory;
};

function getStorageGlobals(): StorageGlobals {
  const g = globalThis as Record<string, unknown>;

  if (!g[STORAGE_GLOBALS_KEY]) {
    g[STORAGE_GLOBALS_KEY] = {};
  }

  return g[STORAGE_GLOBALS_KEY] as StorageGlobals;
}

const NODE_FILE_STORAGE_NOT_REGISTERED_ERROR = 'Node file storage was requested, but no factory is registered';

/**
 * Hands this module the Node-only file storage. The implementation pulls Node built-ins, so
 * importing it from here would drag those into the module graph of every browser bundle and each
 * bundler config would have to stub it back out. Keeping the import on the Node host instead means
 * a browser build cannot reach the implementation by construction, and the storage stays
 * unavailable rather than half-wired: an unregistered factory throws below. It is kept with the
 * other globals so that registering through one copy of this module is visible to all of them.
 */
export function registerNodeFileStorageFactory(factory: NodeFileStorageFactory) {
  getStorageGlobals().nodeFileStorageFactory = factory;
}

export const storage: Storage = createStorageFacade(() => getCurrentStorage());

export function createStorage(storageConfig?: ApiStorageConfig) {
  return storageConfig ? resolveStorage(storageConfig) : resolveDefaultStorage();
}

export function getCurrentStorage() {
  const runtimeStorage = getStorageContext()?.getStore();

  if (runtimeStorage) {
    return runtimeStorage;
  }

  const globals = getStorageGlobals();

  if (isBrowserSingleRuntimeStorageAllowed() && globals.legacyStorage) {
    return globals.legacyStorage;
  }

  throw new Error('Storage access requires an explicit runtime storage context');
}

export function withStorage<T>(storageInstance: Storage, fn: () => T) {
  const context = getStorageContext();

  return context ? context.run(storageInstance, fn) : fn();
}

export function configureStorage(storageConfig?: ApiStorageConfig) {
  const nextStorage = createStorage(storageConfig);

  if (isBrowserSingleRuntimeStorageAllowed()) {
    getStorageGlobals().legacyStorage = nextStorage;
  }

  return nextStorage;
}

export default {
  ...storages,
  [StorageType.NodeFile]: createNodeFileStorage,
};

function createStorageFacade(resolveStorageInstance: () => Storage): Storage {
  return {
    getItem(name, force) {
      return resolveStorageInstance().getItem(name, force);
    },
    setItem(name, value) {
      return resolveStorageInstance().setItem(name, value);
    },
    async mutateItem(name, mutate) {
      const storageInstance = resolveStorageInstance();

      if (storageInstance.mutateItem) {
        return storageInstance.mutateItem(name, mutate);
      }

      const nextValue = mutate(await storageInstance.getItem(name));
      if (nextValue !== undefined) {
        await storageInstance.setItem(name, nextValue);
      } else {
        await storageInstance.removeItem(name);
      }
      return nextValue;
    },
    removeItem(name) {
      return resolveStorageInstance().removeItem(name);
    },
    clear() {
      return resolveStorageInstance().clear();
    },
    async getAll() {
      const storageInstance = resolveStorageInstance();

      if (storageInstance.getAll) {
        return storageInstance.getAll();
      }

      return {};
    },
    async setMany(items) {
      const storageInstance = resolveStorageInstance();

      if (storageInstance.setMany) {
        await storageInstance.setMany(items);
        return;
      }

      await Promise.all(
        Object.entries(items).map(([key, value]) => storageInstance.setItem(key as StorageKey, value)),
      );
    },
    async getMany(keys) {
      const storageInstance = resolveStorageInstance();

      if (storageInstance.getMany) {
        return storageInstance.getMany(keys);
      }

      const entries = await Promise.all(
        keys.map(async (key) => [key, await storageInstance.getItem(key as StorageKey)] as const),
      );

      return Object.fromEntries(entries);
    },
  };
}

function resolveDefaultStorage() {
  return IS_EXTENSION ? extensionStorage : IS_AIR_APP ? airStorage : idb;
}

function resolveStorage(storageConfig: ApiStorageConfig) {
  if (storageConfig.type === 'nodeFile') {
    return createNodeFileStorage(storageConfig);
  }

  return resolveDefaultStorage();
}

function createNodeFileStorage(storageConfig: NodeFileStorageConfig) {
  const bundledNodeFileModule = loadBundledNodeFileStorageModule();

  if (bundledNodeFileModule) {
    return bundledNodeFileModule.createNodeFileStorage(storageConfig);
  }

  const { nodeFileStorageFactory } = getStorageGlobals();

  if (!nodeFileStorageFactory) {
    throw new Error(NODE_FILE_STORAGE_NOT_REGISTERED_ERROR);
  }

  return nodeFileStorageFactory(storageConfig);
}

function loadBundledNodeFileStorageModule() {
  const payloadDir = process.env.MTW_HEADLESS_BUNDLE_PAYLOAD_DIR;

  if (!payloadDir) {
    return undefined;
  }

  const modulePath = resolveBundledNodeFileModulePath(payloadDir);

  if (typeof process.mainModule?.require !== 'function') {
    return undefined;
  }

  return process.mainModule.require(modulePath) as typeof import('./nodeFile');
}

function resolveBundledNodeFileModulePath(payloadDir: string) {
  return joinFilePath(payloadDir, 'nodeFile.cjs');
}

function getStorageContext() {
  const globals = getStorageGlobals();

  if (globals.storageContext !== undefined) {
    return globals.storageContext || undefined;
  }

  const require = getNodeBuiltinRequire();

  if (!require) {
    globals.storageContext = false;
    return undefined;
  }

  try {
    const { AsyncLocalStorage } = require('node:async_hooks') as typeof import('node:async_hooks');

    globals.storageContext = new AsyncLocalStorage<Storage>();
    return globals.storageContext;
  } catch (_err) {
    globals.storageContext = false;
    return undefined;
  }
}

function isBrowserSingleRuntimeStorageAllowed() {
  return typeof window !== 'undefined'
    || typeof document !== 'undefined'
    || typeof importScripts === 'function'
    || typeof WorkerGlobalScope !== 'undefined'
    || Boolean(process.env.MTW_HEADLESS_BUNDLE_PAYLOAD_DIR);
}

function getOptionalRequire() {
  try {
    const indirectRequire = globalThis.eval?.('require');

    if (typeof indirectRequire === 'function') {
      return indirectRequire as NodeJS.Require;
    }
  } catch (_err) {
    // Ignore environments where `require` is not visible to indirect eval.
  }

  if (typeof require === 'function') {
    return require;
  }

  if (typeof module !== 'undefined' && typeof module.require === 'function') {
    return module.require.bind(module) as NodeJS.Require;
  }

  return undefined;
}

// Webpack rewrites `require` references into its own runtime stub, which can't resolve Node
// built-ins (e.g. `node:async_hooks`). When the bundle runs under Node, `process.mainModule.require`
// is the real Node CommonJS require; prefer it so built-ins remain reachable.
function getNodeBuiltinRequire() {
  if (
    typeof process !== 'undefined'
    && process.mainModule
    && typeof process.mainModule.require === 'function'
  ) {
    return process.mainModule.require.bind(process.mainModule) as NodeJS.Require;
  }

  return getOptionalRequire();
}

function joinFilePath(directoryPath: string, fileName: string) {
  if (!directoryPath) {
    return fileName;
  }

  const separator = directoryPath.includes('\\') ? '\\' : '/';
  const trimmedDirectoryPath = directoryPath.replace(/[\\/]+$/, '');

  return `${trimmedDirectoryPath}${separator}${fileName}`;
}

type StorageContext = {
  getStore(): Storage | undefined;
  run<T>(store: Storage, callback: () => T): T;
};
