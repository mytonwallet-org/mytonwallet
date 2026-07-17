import type { StorageKey } from '../../../api/storages/types';

// These functions declare the window-side method contract for the native Air secure-storage bridge.
// In the Air app the calls are routed through `airAppCallWindow` and served natively; in web, extension
// and Electron the secure storage path is never taken (idb is the default storage). The bodies are
// therefore unreachable and exist only to define the bridge signatures.

function notAvailable(): Promise<never> {
  return Promise.reject(new Error('Air secure storage is not available in this build'));
}

export function airStorageGetItem(_key: StorageKey): Promise<string | undefined> {
  return notAvailable();
}

export function airStorageSetItem(_key: StorageKey, _value: string): Promise<{ value: boolean }> {
  return notAvailable();
}

export function airStorageRemoveItem(_key: StorageKey): Promise<{ value: boolean }> {
  return notAvailable();
}

export function airStorageClear(): Promise<{ value: boolean }> {
  return notAvailable();
}

export function airStorageKeys(): Promise<{ value: string[] }> {
  return notAvailable();
}
