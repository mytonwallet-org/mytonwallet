import type { ChainSdk } from '../../types/chains';

import { fetchActivityDetails, fetchActivitySlice } from './activities';
import { getWalletFromAddress, getWalletFromBip39Mnemonic } from './auth';
import { setupActivePolling, setupInactivePolling } from './polling';
import { checkTransactionDraft, submitTransfer } from './transfer';

function notSupported(): never {
  throw new Error('Not supported in Tron');
}

const tronSdk: ChainSdk<'tron'> = {
  fetchActivitySlice,
  fetchActivityDetails,
  decryptComment: notSupported,
  getWalletFromBip39Mnemonic,
  getWalletFromAddress,
  // A note for the future implementation:
  // In contrast to TON, Tron doesn't allow loading balances of multiple wallets in 1 request. Loading a wallet from
  // Ledger is relatively slow. So, to parallelize and speed up the loading, each balance should be loaded as soon as
  // the corresponding wallet is loaded from Ledger.
  getWalletsFromLedgerAndLoadBalance: notSupported,
  setupActivePolling,
  setupInactivePolling,
  checkTransactionDraft,
  submitTransfer,
  verifyLedgerWalletAddress: notSupported,
  getIsLedgerAppOpen: notSupported,
};

export default tronSdk;
