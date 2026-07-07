import { BrowserWindow, dialog, ipcMain, nativeTheme } from 'electron';

import { ElectronAction } from './types';

import { checkIsKycUrlAllowed, parseWalletConnectPayDataCollectionMessage } from '../util/walletConnectPay';
import { focusMainWindow, mainWindow } from './utils';

const COLLECT_LOG_PREFIX = '[wc-pay-collect]';

// ERR_ABORTED, fired for superseded navigations (the spinner -> KYC handoff); not a real failure
const ERR_ABORTED = -3;

// Shown in the KYC window while pay.walletconnect.com loads; pure CSS, no scripts or external resources
const COLLECT_SPINNER_PAGE_URL = `data:text/html;charset=utf-8,${encodeURIComponent(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<style>
  html, body { margin: 0; height: 100%; background: #ffffff; }
  body { display: flex; align-items: center; justify-content: center; }
  .spinner {
    width: 40px;
    height: 40px;
    border: 3px solid #d9d9d9;
    border-top-color: #007aff;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-color-scheme: dark) {
    html, body { background: #181818; }
    .spinner { border-color: #3a3a3a; border-top-color: #469cff; }
  }
</style>
</head>
<body><div class="spinner"></div></body>
</html>`)}`;

const MAX_CONFIRM_STRING_LENGTH = 200;

interface CollectConfirmStrings {
  message: string;
  continueText: string;
  cancelText: string;
}

// Fallback used when the renderer-supplied strings fail validation (IPC is a security boundary)
const COLLECT_CONFIRM_FALLBACK: CollectConfirmStrings = {
  message: 'Are you sure you want to cancel the payment?',
  continueText: 'Continue',
  cancelText: 'Cancel Payment',
};

let collectWindow: BrowserWindow | undefined;

function assertKycUrl(url: string) {
  if (!checkIsKycUrlAllowed(url)) {
    throw new Error('Invalid WalletConnect Pay KYC URL');
  }
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

function sanitizeConfirmStrings(value: unknown): CollectConfirmStrings {
  if (!value || typeof value !== 'object') {
    return COLLECT_CONFIRM_FALLBACK;
  }

  const { message, continueText, cancelText } = value as Record<string, unknown>;
  if (!isNonEmptyString(message) || !isNonEmptyString(continueText) || !isNonEmptyString(cancelText)) {
    return COLLECT_CONFIRM_FALLBACK;
  }

  return {
    message: message.slice(0, MAX_CONFIRM_STRING_LENGTH),
    continueText: continueText.slice(0, MAX_CONFIRM_STRING_LENGTH),
    cancelText: cancelText.slice(0, MAX_CONFIRM_STRING_LENGTH),
  };
}

function closeCollectWindow() {
  if (collectWindow && !collectWindow.isDestroyed()) {
    collectWindow.close();
  }

  collectWindow = undefined;
}

function installCollectMessageBridge(contents: Electron.WebContents) {
  return contents.executeJavaScript(`
    (function() {
      if (window.__wcPayCollectBridgeInstalled) {
        return;
      }

      window.__wcPayCollectBridgeInstalled = true;

      function reportCollectMessage(data) {
        if (data?.type === 'IC_COMPLETE' || data?.type === 'IC_ERROR') {
          console.info('${COLLECT_LOG_PREFIX} ' + JSON.stringify(data));
        }
      }

      function handleBridgePayload(message) {
        try {
          const data = typeof message === 'string' ? JSON.parse(message) : message;
          reportCollectMessage(data);
        } catch {}
      }

      // Standalone BrowserWindow has no parent frame; WC Pay webview-bridge falls back to this.
      window.ReactNativeWebView = {
        postMessage: handleBridgePayload,
      };

      window.addEventListener('message', (event) => {
        handleBridgePayload(event.data);
      });
    })();
  `);
}

function getConsoleMessageText(
  _event: Electron.Event,
  levelOrDetails: number | { message: string },
  message?: string,
): string | undefined {
  if (typeof levelOrDetails === 'object') {
    return levelOrDetails.message;
  }

  return message;
}

function handleCollectBridgeMessage(
  message: string,
  settle: (handler: () => void) => void,
  resolve: () => void,
  reject: (reason?: Error) => void,
) {
  const prefixIndex = message.indexOf(COLLECT_LOG_PREFIX);
  if (prefixIndex === -1) {
    return;
  }

  try {
    const data = parseWalletConnectPayDataCollectionMessage(
      message.slice(prefixIndex + COLLECT_LOG_PREFIX.length).trim(),
    );

    if (!data) {
      return;
    }

    if (data.type === 'IC_COMPLETE') {
      if (data.success === false) {
        settle(() => reject(new Error(data.error || 'Unknown error')));
        return;
      }

      settle(resolve);
    } else if (data.type === 'IC_ERROR') {
      settle(() => reject(new Error(data.error || 'Unknown error')));
    }
  } catch {
    // Ignore malformed bridge payloads
  }
}

function openCollectWindow(url: string, confirmStrings: CollectConfirmStrings): Promise<void> {
  assertKycUrl(url);

  closeCollectWindow();

  return new Promise((resolve, reject) => {
    let settled = false;

    const settle = (handler: () => void) => {
      if (settled) {
        return;
      }

      settled = true;
      closeCollectWindow();
      focusMainWindow();
      handler();
    };

    collectWindow = new BrowserWindow({
      parent: mainWindow,
      modal: true,
      show: false,
      backgroundColor: nativeTheme.shouldUseDarkColors ? '#181818' : '#ffffff',
      width: 450,
      height: 650,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      autoHideMenuBar: true,
      title: 'WalletConnect Pay',
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });

    const { webContents } = collectWindow;

    webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

    webContents.on('will-navigate', (event, newUrl) => {
      if (!checkIsKycUrlAllowed(newUrl)) {
        event.preventDefault();
      }
    });

    let isConfirmingCancel = false;

    const confirmCancel = async () => {
      if (!collectWindow || collectWindow.isDestroyed() || isConfirmingCancel) {
        return;
      }

      const activeWindow = collectWindow;
      isConfirmingCancel = true;
      try {
        const { response } = await dialog.showMessageBox(activeWindow, {
          type: 'question',
          message: confirmStrings.message,
          buttons: [confirmStrings.continueText, confirmStrings.cancelText],
          defaultId: 0,
          cancelId: 0,
        });
        if (response === 1) {
          closeCollectWindow();
        }
      } catch {
        // The window may be destroyed while the dialog is open (e.g. closed via IPC)
      } finally {
        isConfirmingCancel = false;
      }
    };

    // macOS renders modal child windows as sheets without close controls, so Esc is the cancel affordance
    webContents.on('before-input-event', (event, input) => {
      if (input.type === 'keyDown' && input.key === 'Escape') {
        event.preventDefault();
        void confirmCancel();
      }
    });

    const finish = (handler: () => void) => {
      webContents.removeListener('console-message', handleConsoleMessage);
      settle(handler);
    };

    const handleConsoleMessage = (
      event: Electron.Event,
      levelOrDetails: number | { message: string },
      message?: string,
    ) => {
      const consoleMessage = getConsoleMessageText(event, levelOrDetails, message);
      if (!consoleMessage) {
        return;
      }

      handleCollectBridgeMessage(consoleMessage, finish, resolve, reject);
    };

    collectWindow.on('closed', () => {
      collectWindow = undefined;
      webContents.removeListener('console-message', handleConsoleMessage);
      settle(() => reject(new Error('Canceled by the user')));
    });

    webContents.on('console-message', handleConsoleMessage);

    webContents.on('dom-ready', () => {
      void installCollectMessageBridge(webContents);
    });

    webContents.on('did-fail-load', (_event, errorCode, errorDescription, _validatedURL, isMainFrame) => {
      if (isMainFrame && errorCode !== ERR_ABORTED) {
        finish(() => reject(new Error(errorDescription || 'Failed to load')));
      }
    });

    webContents.on('did-finish-load', () => {
      void installCollectMessageBridge(webContents);
    });

    void webContents.loadURL(COLLECT_SPINNER_PAGE_URL).then(() => {
      if (!collectWindow || collectWindow.isDestroyed()) {
        return;
      }

      collectWindow.show();
      void webContents.loadURL(url).catch(() => {}); // load failures are surfaced via did-fail-load
    }).catch(() => {}); // rejects with ERR_ABORTED if the window is closed before the spinner page loads
  });
}

export function setupWalletConnectPayCollectHandlers() {
  ipcMain.handle(ElectronAction.OPEN_WALLET_CONNECT_PAY_COLLECT, async (_, url: string, confirmStrings: unknown) => {
    return openCollectWindow(url, sanitizeConfirmStrings(confirmStrings));
  });

  ipcMain.handle(ElectronAction.CLOSE_WALLET_CONNECT_PAY_COLLECT, () => {
    closeCollectWindow();
  });
}
