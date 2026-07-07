import type { StorageKey } from '../api/storages/types';

import { INDEXED_DB_NAME, INDEXED_DB_STORE_NAME } from '../config';
import { buildRestoreLocalStorageScript, getRestorableLocalStorageEntries } from './storageScripts';
import { checkIsWebContentsUrlAllowed, mainWindow } from './utils';

let capturedLocalStorage: Record<string, any> | undefined;
let capturedIdb: { key: StorageKey; value: any }[] | undefined;

export function captureStorage(): Promise<[void, void]> {
  return Promise.all([captureLocalStorage(), captureIdb()]);
}

export function restoreStorage(): Promise<[void, void]> {
  return Promise.all([restoreLocalStorage(), restoreIdb()]);
}

async function captureLocalStorage(): Promise<void> {
  const contents = mainWindow.webContents;
  const contentsUrl = contents.getURL();

  if (!checkIsWebContentsUrlAllowed(contentsUrl)) {
    return;
  }

  capturedLocalStorage = await contents.executeJavaScript('({ ...localStorage });');
}

async function captureIdb(): Promise<void> {
  const contents = mainWindow.webContents;
  const contentsUrl = contents.getURL();

  if (!checkIsWebContentsUrlAllowed(contentsUrl)) {
    return;
  }

  capturedIdb = await contents.executeJavaScript(`
    new Promise((resolve) => {
      const request = window.indexedDB.open('${INDEXED_DB_NAME}');

      request.onupgradeneeded = (event) => {
        event.target.transaction.abort();
        resolve();
      }

      request.onsuccess = (event) => {
        const result = [];

        const db = event.target.result;
        const transaction = db.transaction(['${INDEXED_DB_STORE_NAME}'], 'readonly');
        const store = transaction.objectStore('${INDEXED_DB_STORE_NAME}');

        store.openCursor().onsuccess = (e) => {
          const cursor = e.target.result;
          if (cursor) {
            result.push({ key: cursor.key, value: cursor.value });
            cursor.continue();
          } else {
            resolve(result);
          }
        };

        transaction.oncomplete = () => {
          db.close();
        };

        transaction.onerror = () => {
          resolve();
        };
      }

      request.onerror = () => {
        resolve();
      };
    });
  `);
}

export async function restoreLocalStorage(): Promise<void> {
  if (!capturedLocalStorage) {
    return;
  }

  const contents = mainWindow.webContents;
  const contentsUrl = contents.getURL();

  if (!checkIsWebContentsUrlAllowed(contentsUrl)) {
    return;
  }

  const entries = getRestorableLocalStorageEntries(capturedLocalStorage);

  if (entries.length) {
    await contents.executeJavaScript(buildRestoreLocalStorageScript(entries));
  }

  capturedLocalStorage = undefined;
}

export async function restoreIdb(): Promise<void> {
  if (!capturedIdb) {
    return;
  }

  const contents = mainWindow.webContents;
  const contentsUrl = contents.getURL();

  if (!checkIsWebContentsUrlAllowed(contentsUrl)) {
    return;
  }

  await contents.executeJavaScript(`
    new Promise((resolve) => {
      const request = window.indexedDB.open('${INDEXED_DB_NAME}');

      request.onupgradeneeded = (event) => {
        const db = event.target.result;

        if (!db.objectStoreNames.contains('${INDEXED_DB_STORE_NAME}')) {
          db.createObjectStore('${INDEXED_DB_STORE_NAME}');
        }
      }

      request.onsuccess = (event) => {
        const result = {};

        const db = event.target.result;
        const transaction = db.transaction(['${INDEXED_DB_STORE_NAME}'], 'readwrite');
        const store = transaction.objectStore('${INDEXED_DB_STORE_NAME}');

        ${JSON.stringify(capturedIdb)}.forEach(item => {
          store.put(item.value, item.key);
        });

        transaction.oncomplete = () => {
          db.close();
          resolve();
        };

        transaction.onerror = () => {
          resolve();
        };
      }

      request.onerror = () => {
        resolve();
      };
    });
  `);

  capturedIdb = undefined;
}
