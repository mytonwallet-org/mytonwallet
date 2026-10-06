import extension from 'webextension-polyfill';

import { DEFAULT_PORTRAIT_WINDOW_SIZE } from '../../config';
import { getExtensionWindowIds } from '../../util/extensionWindow';
import { createDappPromise, rejectAllDappPromises } from '../common/dappPromises';
import storage from '../storages/extension';

const { chrome } = self;

let currentWindowId: number | undefined;
let readyPromise: Promise<void> | undefined = createDappPromise('whenPopupReady').promise;
let ensureWindowPromise: Promise<number> | undefined;

const WINDOW_DEFAULTS = {
  top: 120,
  left: 20,
  ...DEFAULT_PORTRAIT_WINDOW_SIZE,
};
const MARGIN_RIGHT = 20;
const WINDOW_STATE_MONITOR_INTERVAL = 3000;
const MINIMAL_WINDOW = 100;

type WindowBounds = { left: number; top: number; width: number; height: number };

(function init() {
  if (!chrome) {
    return;
  }

  void getDisplays().then(([firstScreen]) => {
    if (firstScreen) {
      WINDOW_DEFAULTS.left = firstScreen.bounds.width - WINDOW_DEFAULTS.width - MARGIN_RIGHT;
    }
  });

  extension.action.onClicked.addListener(openPopupWindow);

  extension.windows.onRemoved.addListener((removedWindowId) => {
    if (removedWindowId !== currentWindowId) {
      return;
    }

    rejectAllDappPromises('Extension popup closed');

    currentWindowId = undefined;
    readyPromise = undefined;
  });

  setInterval(async () => {
    const currentWindow = await extension.windows.getCurrent();
    if (!currentWindow || currentWindow.id !== currentWindowId) {
      return;
    }

    const { height = 0, width = 0 } = currentWindow;
    const correctHeight = Math.max(height, MINIMAL_WINDOW);
    const correctWidth = Math.max(width, MINIMAL_WINDOW);

    void storage.setItem('windowState', {
      top: currentWindow.top,
      left: currentWindow.left,
      height: correctHeight,
      width: correctWidth,
    });

    if (height < MINIMAL_WINDOW || width < MINIMAL_WINDOW) {
      await extension.windows.update(currentWindowId!, {
        height: MINIMAL_WINDOW,
        width: MINIMAL_WINDOW,
      });
    }
  }, WINDOW_STATE_MONITOR_INTERVAL);
}());

export async function openPopupWindow() {
  await updatePopupWindow({ focused: true });

  return readyPromise;
}

async function updatePopupWindow(updateInfo: Parameters<typeof extension.windows.update>[1]) {
  const windowId = await ensurePopupWindow();

  try {
    await applyPopupWindowUpdate(windowId, updateInfo);
  } catch {
    if (currentWindowId === windowId) {
      currentWindowId = undefined;
      await storage.removeItem('windowId');
    }

    const recoveredWindowId = await ensurePopupWindow();
    await applyPopupWindowUpdate(recoveredWindowId, updateInfo);
  }
}

async function applyPopupWindowUpdate(windowId: number, updateInfo: Parameters<typeof extension.windows.update>[1]) {
  if (updateInfo.width !== undefined && updateInfo.height !== undefined && chrome?.system) {
    const window = await extension.windows.get(windowId);
    const currentBounds = {
      left: window.left ?? WINDOW_DEFAULTS.left,
      top: window.top ?? WINDOW_DEFAULTS.top,
      width: window.width ?? WINDOW_DEFAULTS.width,
      height: window.height ?? WINDOW_DEFAULTS.height,
    };
    const bounds = await fitBoundsToDisplay({
      ...currentBounds, width: updateInfo.width, height: updateInfo.height,
    }, currentBounds);
    await extension.windows.update(windowId, { ...updateInfo, ...bounds });
    return;
  }

  await extension.windows.update(windowId, updateInfo);
}

async function fitBoundsToDisplay(bounds: WindowBounds, anchor = bounds): Promise<WindowBounds> {
  const displays = await getDisplays();
  let selected = displays.find((display) => display.isPrimary) ?? displays[0];
  let largestOverlap = 0;
  for (const display of displays) {
    const area = display.workArea;
    const width = Math.max(0, Math.min(anchor.left + anchor.width, area.left + area.width)
      - Math.max(anchor.left, area.left));
    const height = Math.max(0, Math.min(anchor.top + anchor.height, area.top + area.height)
      - Math.max(anchor.top, area.top));
    if (width * height > largestOverlap) {
      largestOverlap = width * height;
      selected = display;
    }
  }
  if (!selected) return bounds;

  const area = selected.workArea;
  const width = Math.min(bounds.width, area.width);
  const height = Math.min(bounds.height, area.height);
  return {
    width,
    height,
    left: Math.max(area.left, Math.min(bounds.left, area.left + area.width - width)),
    top: Math.max(area.top, Math.min(bounds.top, area.top + area.height - height)),
  };
}

function getDisplays(): Promise<chrome.system.display.DisplayUnitInfo[]> {
  if (!chrome?.system?.display?.getInfo) return Promise.resolve([]);

  return new Promise((resolve) => {
    try {
      chrome.system.display.getInfo((displays) => {
        resolve(chrome.runtime.lastError ? [] : displays ?? []);
      });
    } catch {
      resolve([]);
    }
  });
}

function ensurePopupWindow() {
  ensureWindowPromise ??= resolveOrCreatePopupWindow().finally(() => {
    ensureWindowPromise = undefined;
  });

  return ensureWindowPromise;
}

async function resolveOrCreatePopupWindow() {
  const { windowIds, isComplete } = await getExtensionWindowIds().catch(() => ({
    windowIds: [], isComplete: false,
  }));
  const ownWindowIds = new Set(windowIds);
  const storedWindowId = await storage.getItem('windowId');
  const lastWindowId = typeof storedWindowId === 'number' ? storedWindowId : undefined;
  const candidateIds = Array.from(new Set(
    [currentWindowId, lastWindowId].filter((windowId): windowId is number => typeof windowId === 'number'),
  ));

  for (const windowId of candidateIds) {
    try {
      const candidate = await extension.windows.get(windowId, { populate: true });
      if (isOwnPopupWindow(candidate, ownWindowIds)) {
        bindPopupWindow(windowId);
        return windowId;
      }
    } catch {
      continue;
    }
  }

  const existingWindows = await extension.windows.getAll({
    populate: true,
    windowTypes: ['popup'],
  });
  const existingWindow = existingWindows.find((window) => isOwnPopupWindow(window, ownWindowIds));
  if (typeof existingWindow?.id === 'number') {
    bindPopupWindow(existingWindow.id);
    return existingWindow.id;
  }

  if (!isComplete) throw new Error('Extension window discovery is incomplete');

  currentWindowId = undefined;
  readyPromise = undefined;
  if (typeof lastWindowId === 'number') {
    await storage.removeItem('windowId');
  }

  await createWindow();
  return currentWindowId!;
}

function isOwnPopupWindow(window: Awaited<ReturnType<typeof extension.windows.get>>, ownWindowIds: Set<number>) {
  const popupUrl = extension.runtime.getURL('index.html');

  return window.type === 'popup' && (ownWindowIds.has(window.id!) || window.tabs?.some((tab) => (
    tab.url === popupUrl || tab.pendingUrl === popupUrl
  )));
}

function bindPopupWindow(windowId: number) {
  currentWindowId = windowId;
  void storage.setItem('windowId', windowId);
}

async function createWindow(isRetryingWithoutLastState = false): Promise<void> {
  readyPromise ??= createDappPromise('whenPopupReady').promise;
  const lastState = !isRetryingWithoutLastState ? await storage.getItem('windowState') : undefined;

  try {
    const bounds = await fitBoundsToDisplay({ ...WINDOW_DEFAULTS, ...lastState });
    const window = await extension.windows.create({
      ...bounds,
      url: 'index.html',
      type: 'popup',
      focused: true,
    });

    if (!window) {
      throw new Error('Failed to create extension window');
    }

    currentWindowId = window.id;
    void storage.setItem('windowId', currentWindowId);
  } catch (err) {
    if (!isRetryingWithoutLastState) {
      await createWindow(true);
    } else {
      throw err;
    }
  }
}

export async function clearCache() {
  await extension.webRequest.handlerBehaviorChanged();
}

export async function updateWindowSize(size: { width: number; height: number }) {
  await updatePopupWindow(size);
}
