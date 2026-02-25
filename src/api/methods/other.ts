import nacl from 'tweetnacl';

import type { LangCode, Theme } from '../../global/types';
import type { StorageKey } from '../storages/types';
import type { ApiAnyDisplayError, ApiBaseCurrency, ApiChain } from '../types';

import { setIsAppFocused } from '../../util/focusAwareDelay';
import { getLogs, logDebugError } from '../../util/logs';
import { pause } from '../../util/schedulers';
import chains from '../chains';
import { fetchStoredAccounts, fetchStoredWallet, updateStoredWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { hexToBytes } from '../common/utils';
import { SEC } from '../constants';
import { handleServerError } from '../errors';
import { storage } from '../storages';

import RECEIVE_GRADIENT_SVGS from '../../assets/receiveGradientSvgs';

const SIGN_MESSAGE = Buffer.from('MyTonWallet_AuthToken_n6i0k4w8pb');

export async function getBackendAuthToken(accountId: string, password: string) {
  const accountWallet = await fetchStoredWallet(accountId, 'ton');
  let { authToken } = accountWallet;
  const { publicKey, isInitialized } = accountWallet;

  if (!authToken) {
    const privateKey = await chains.ton.fetchPrivateKeyString(accountId, password);
    const signature = nacl.sign.detached(SIGN_MESSAGE, hexToBytes(privateKey!));
    authToken = Buffer.from(signature).toString('base64');

    await updateStoredWallet(accountId, 'ton', {
      authToken,
    });
  }

  if (!isInitialized) {
    authToken += `:${publicKey}`;
  }

  return authToken;
}

export async function fetchAccountConfigForDebugPurposesOnly() {
  try {
    const [accounts, stateVersion, mnemonicsEncrypted] = await Promise.all([
      fetchStoredAccounts(),
      storage.getItem('stateVersion'),
      storage.getItem('mnemonicsEncrypted' as StorageKey),
    ]);

    return JSON.stringify({ accounts, stateVersion, mnemonicsEncrypted });
  } catch (err) {
    logDebugError('fetchAccountConfigForDebugPurposesOnly', err);

    return undefined;
  }
}

export function ping() {
  return true;
}

export { setIsAppFocused, getLogs };

export function getLangCode() {
  return storage.getItem('langCode') as Promise<LangCode | undefined>;
}

export function setLangCode(langCode: LangCode) {
  return storage.setItem('langCode', langCode);
}

export async function getMoonpayOnrampUrl({
  chain,
  address,
  theme,
  currency,
}: {
  chain: ApiChain;
  address: string;
  theme: Theme;
  currency: ApiBaseCurrency;
}) {
  try {
    return await callBackendGet<{ url: string }>('/onramp-url', {
      chain,
      address,
      theme,
      currency: currency.toLowerCase(),
    });
  } catch (err) {
    logDebugError('getMoonpayOnrampUrl', err);

    return handleServerError(err);
  }
}

export async function getMoonpayOfframpUrl({
  chain,
  address,
  theme,
  currency,
  amount,
  baseUrl,
}: {
  chain: ApiChain;
  address: string;
  theme: Theme;
  currency: ApiBaseCurrency;
  amount: string;
  baseUrl: string;
}) {
  try {
    return await callBackendGet<{ url: string }>('/offramp-url', {
      chain,
      address,
      theme,
      currency: currency.toLowerCase(),
      amount,
      baseUrl,
    });
  } catch (err) {
    logDebugError('getMoonpayOfframpUrl', err);

    return handleServerError(err);
  }
}

export function waitForLedgerApp(
  chain: ApiChain,
  options: {
    timeout?: number;
    attemptPause?: number;
  } = {},
): Promise<boolean | { error: ApiAnyDisplayError }> {
  const { timeout = 1.25 * SEC, attemptPause = 0.125 * SEC } = options;

  let hasTimedOut = false;

  const waitForDeadline = async () => {
    await pause(timeout);
    hasTimedOut = true;
    return false;
  };

  const checkApp = async () => {
    while (!hasTimedOut) {
      try {
        const result = await chains[chain].getIsLedgerAppOpen();
        if (typeof result === 'object' && 'error' in result) return result;

        if (result) {
          return true;
        }
      } catch (err) {
        logDebugError('waitForLedgerApp', chain, err);
      }

      await pause(attemptPause);
    }

    return false;
  };

  return Promise.race([waitForDeadline(), checkApp()]);
}

export async function renderBlurredReceiveBg(
  chain: ApiChain,
  opts?: {
    width?: number;
    height?: number;
    blurPx?: number;
    quality?: number;
    overlay?: string;
    scale?: number;
  },
): Promise<string> {
  const { width = 412, height = 422, blurPx = 24, quality = 0.85, overlay = '#ffffff', scale = 1 } = opts ?? {};

  const svg = RECEIVE_GRADIENT_SVGS[chain];

  const svgBlob = new Blob([svg], {
    type: 'image/svg+xml;charset=utf-8',
  });

  const url = URL.createObjectURL(svgBlob);

  return new Promise((resolve, reject) => {
    const img = new Image();
    img.decoding = 'async';

    img.onload = () => {
      try {
        const outW = Math.max(1, Math.round(width * scale));
        const outH = Math.max(1, Math.round(height * scale));
        const padW = outW + 2 * blurPx;
        const padH = outH + 2 * blurPx;

        const padCanvas = document.createElement('canvas');
        padCanvas.width = padW;
        padCanvas.height = padH;

        const padCtx = padCanvas.getContext('2d');
        if (!padCtx) {
          reject(new Error('2D context not available'));
          return;
        }

        padCtx.filter = `blur(${blurPx}px)`;
        padCtx.drawImage(img, 0, 0, padW, padH);
        padCtx.filter = 'none';

        const canvas = document.createElement('canvas');
        canvas.width = outW;
        canvas.height = outH;

        const ctx = canvas.getContext('2d');
        if (!ctx) {
          reject(new Error('2D context not available'));
          return;
        }

        ctx.drawImage(padCanvas, blurPx, blurPx, outW, outH, 0, 0, outW, outH);

        // Overlay tint color (blur overlay effect)
        if (overlay) {
          ctx.globalCompositeOperation = 'source-over';
          ctx.fillStyle = overlay;
          ctx.fillRect(0, 0, outW, outH);
        }

        // Export
        canvas.toBlob(
          async (blob) => {
            if (!blob) {
              reject(new Error('Canvas toBlob failed'));
              return;
            }

            try {
              const dataUrl = await blobToDataURL(blob);
              resolve(dataUrl);
            } catch (e) {
              reject(e);
            } finally {
              URL.revokeObjectURL(url);
            }
          },
          'image/jpeg',
          quality,
        );
      } catch (err) {
        URL.revokeObjectURL(url);
        reject(err);
      }
    };

    img.onerror = (e) => {
      URL.revokeObjectURL(url);
      reject(new Error('Failed to load SVG in Image element'));
    };

    img.src = url;
  });
}

/** Convert Blob -> data URL */
async function blobToDataURL(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer();
  const bytes = new Uint8Array(buf);

  // Convert to base64 without stack overflows for large images
  let binary = '';
  const chunkSize = 0x8000; // 32KB
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  const base64 = btoa(binary);
  return `data:${blob.type};base64,${base64}`;
}
