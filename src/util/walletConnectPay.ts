import type { ApiNetwork } from '../api/types';
import type { Account } from '../global/types';
import {
  EVM_CHAIN_IDS,
  SOLANA_CHAIN_IDS,
} from '../api/dappProtocols/adapters/walletConnect/types';

import isViewAccount from './isViewAccount';

export const WALLET_CONNECT_PAY_ACCOUNT_SWITCHED = 'Account switched';

const WALLET_CONNECT_PAY_COLLECT_HOST = 'pay.walletconnect.com';

export function isWalletConnectPayUserCancellation(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);

  return message === 'Canceled by the user';
}

export function isWalletConnectPayAccountSwitch(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);

  return message === WALLET_CONNECT_PAY_ACCOUNT_SWITCHED;
}

export function doesAccountSupportWalletConnectPay(account: Account, network: ApiNetwork): boolean {
  if (isViewAccount(account.type)) {
    return false;
  }

  for (const entry of Object.values(EVM_CHAIN_IDS)) {
    if (entry.network === network && account.byChain[entry.chain]?.address) {
      return true;
    }
  }

  if (!account.byChain.solana?.address) {
    return false;
  }

  return Object.values(SOLANA_CHAIN_IDS).some((entry) => entry.network === network);
}

/** WalletConnect Pay collect pages allow embedding only from https parents (`frame-ancestors https:`). */
export function canEmbedWalletConnectPayCollect(): boolean {
  return window.location.protocol === 'https:';
}

/** WalletConnect Pay collect pages are served only from `pay.walletconnect.com` over https. */
export function checkIsKycUrlAllowed(url: string): boolean {
  try {
    const { protocol, hostname } = new URL(url);

    return protocol === 'https:' && hostname === WALLET_CONNECT_PAY_COLLECT_HOST;
  } catch {
    return false;
  }
}

export type WalletConnectPayDataCollectionHandlers = {
  onComplete: NoneToVoidFunction;
  onError: (error: string) => void;
};

export type WalletConnectPayDataCollectionMessage = {
  type?: 'IC_COMPLETE' | 'IC_ERROR';
  success?: boolean;
  error?: string;
};

export function parseWalletConnectPayDataCollectionMessage(
  rawData: unknown,
): WalletConnectPayDataCollectionMessage | undefined {
  if (rawData === undefined) {
    return undefined;
  }

  const data = typeof rawData === 'string' ? JSON.parse(rawData) : rawData;

  if (!data || typeof data !== 'object' || typeof (data as WalletConnectPayDataCollectionMessage).type !== 'string') {
    return undefined;
  }

  return data as WalletConnectPayDataCollectionMessage;
}

/**
 * Listens for WalletConnect Pay data-collection iframe messages (`IC_COMPLETE` / `IC_ERROR`).
 * @see https://docs.walletconnect.com/payments/wallets/walletkit/web
 */
export function listenWalletConnectPayDataCollectionMessages(
  expectedOrigin: string | undefined,
  handlers: WalletConnectPayDataCollectionHandlers,
  expectedSource?: MessageEventSource,
): NoneToVoidFunction {
  function handleMessage(event: MessageEvent) {
    if (expectedOrigin && event.origin !== expectedOrigin) {
      return;
    }

    if (expectedSource !== undefined && event.source !== expectedSource) {
      return;
    }

    try {
      const data = parseWalletConnectPayDataCollectionMessage(event.data);

      if (data?.type === 'IC_COMPLETE') {
        if (data.success === false) {
          handlers.onError(data.error || 'Unknown error');
          return;
        }

        handlers.onComplete();
      } else if (data?.type === 'IC_ERROR') {
        handlers.onError(data.error || 'Unknown error');
      }
    } catch {
      // Ignore non-JSON messages
    }
  }

  window.addEventListener('message', handleMessage);

  return () => {
    window.removeEventListener('message', handleMessage);
  };
}

export function getWalletConnectPayCollectOrigin(url: string): string | undefined {
  try {
    return new URL(url).origin;
  } catch {
    return undefined;
  }
}
