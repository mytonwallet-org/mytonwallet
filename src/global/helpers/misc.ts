import type { GlobalState } from '../types';

import { getChainFromAddress } from '../../util/isValidAddress';
import { getChainBySlug, getNativeToken } from '../../util/tokens';
import { getActions } from '../index';
import { selectCurrentAccount } from '../selectors';

import { getInAppBrowser } from '../../components/ui/InAppBrowser';

/**
 * Parses the transfer parameters from the given QR content, assuming it's a plain address.
 * Returns `undefined` if this is not a valid address or the account doesn't have the corresponding wallet.
 */
export function parsePlainAddressQr(global: GlobalState, qrData: string) {
  const availableChains = selectCurrentAccount(global)?.byChain ?? {};
  const newChain = getChainFromAddress(qrData, availableChains, true);
  if (!newChain) {
    return undefined;
  }

  const currentTokenSlug = global.currentTransfer.tokenSlug;
  const currentChain = getChainBySlug(currentTokenSlug);
  const newTokenSlug = newChain !== currentChain ? getNativeToken(newChain).slug : currentTokenSlug;

  return {
    toAddress: qrData,
    tokenSlug: newTokenSlug,
  };
}

export function closeAllOverlays() {
  return Promise.all([
    // It's important to close the in-app browser before closing the modal, because when a modal closes, it calls
    // `show()` on the hidden in-app browser, and calling `close()` right after `show()` causes the app to crash.
    // Meanwhile, calling `close()` before `show()` makes the in-app browser ignore the `show()` call.
    // A situation, where it happens, is pressing an "openUrl" notification while the app shows a TON Connect modal.
    getInAppBrowser()?.close(),
    getActions().closeAnyModal(),
    getActions().closeMediaViewer(),
  ]);
}

/** replaceMap: keys - old (removed) activity ids, value - new (added) activity ids */
export function replaceActivityId(oldId: string | undefined, replaceMap: Record<string, string>) {
  const newId = oldId && replaceMap[oldId];
  return newId || oldId;
}
