import { Address } from '@ton/core';
import type { Wallet } from '@tonconnect/sdk';
import { TonConnectUI } from '@tonconnect/ui';

import { DEBUG } from '../../config';

const MANIFEST_URL = 'https://push.bot/push-tonconnect-manifest.json';

export const tonConnectUi = new TonConnectUI({
  manifestUrl: MANIFEST_URL,
});

export function initTonConnect(
  setWallet: (wallet?: Wallet) => void,
) {
  tonConnectUi.connector.restoreConnection()
    .catch((err) => {
      if (DEBUG) {
        // eslint-disable-next-line no-console
        console.error('Failed to restore connection:', err);
      }
    });

  if (tonConnectUi.connected) {
    setWallet(tonConnectUi.wallet ?? undefined);
  }

  return tonConnectUi.onStatusChange((wallet) => {
    setWallet(wallet || undefined);
  });
}

export function getWalletAddress(wallet: Wallet) {
  return Address.parse(wallet.account.address).toString({ bounceable: false });
}
