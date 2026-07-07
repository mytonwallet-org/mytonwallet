import { ACTIVE_TAB_STORAGE_KEY } from '../config';

export type LocalStorageEntry = readonly [key: string, value: string];

export function getRestorableLocalStorageEntries(localStorage: Record<string, any>): LocalStorageEntry[] {
  return Object.entries(localStorage)
    .filter(([key]) => key !== ACTIVE_TAB_STORAGE_KEY)
    .map(([key, value]) => [key, String(value)] as const);
}

export function buildRestoreLocalStorageScript(entries: LocalStorageEntry[]): string {
  return `
    ${JSON.stringify(entries)}.forEach(([key, value]) => {
      localStorage.setItem(key, value);
    });
  `;
}
