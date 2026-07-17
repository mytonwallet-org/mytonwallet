import type { ChainSdk } from '../../types/chains';
import { DappProtocolType } from '../../dappProtocols/types';

import { fetchActivityDetails, fetchActivitySlice } from './activities';
import { normalizeAddress } from './address';
import {
  fetchPrivateKeyString,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
} from './auth';
import { SOLANA_DERIVATION_PATHS } from './constants';
import { signDappData, signDappTransfers } from './dapp';
import { parseTransactionForPreview } from './emulation';
import {
  checkNftOwnership,
  checkNftTransferDraft,
  getAccountNfts,
  streamAllAccountNfts,
  submitNftTransfers,
} from './nfts';
import { setupActivePolling, setupInactivePolling } from './polling';
import { buildOnchainSwapTransfer, submitOnchainSwapTransfer } from './swap';
import { fetchTransactionById } from './transactionInfo';
import {
  checkTransactionDraft,
  fetchEstimateDiesel,
  sendSignedTransaction,
  submitGasfullTransfer,
  submitGaslessTransfer,
} from './transfer';
import { fetchAccountAssets, getAddressInfo, getWalletBalance } from './wallet';

function notSupported(): never {
  throw new Error('Not supported in Solana');
}

const solanaSdk: ChainSdk<'solana'> = {
  fetchActivitySlice,
  crosschain: undefined,
  fetchActivityDetails,
  decryptComment: notSupported,
  normalizeAddress,
  getDefaultDerivation: () => ({ path: SOLANA_DERIVATION_PATHS.phantom, index: 0, label: 'phantom' }),
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
  getWalletFromAddress,
  getWalletsFromLedgerAndLoadBalance: notSupported,
  setupActivePolling,
  setupInactivePolling,
  fetchToken: notSupported,
  importToken: notSupported,
  checkTransactionDraft,
  fetchEstimateDiesel,
  submitGasfullTransfer,
  submitGaslessTransfer,
  buildOnchainSwapTransfer,
  submitOnchainSwapTransfer,
  getAddressInfo,
  getWalletBalance,
  getWalletAssets: fetchAccountAssets,
  verifyLedgerWalletAddress: notSupported,
  fetchPrivateKeyString,
  getIsLedgerAppOpen: notSupported,
  fetchTransactionById,
  dapp: {
    supportedProtocols: [DappProtocolType.WalletConnect],
    signDappData,
    signDappTransfers,
    parseTransactionForPreview,
    sendSignedTransaction,
  },
  getAccountNfts,
  streamAllAccountNfts,
  checkNftTransferDraft,
  submitNftTransfers,
  checkNftOwnership,
  fetchWalletPermissions: notSupported,
  revokeWalletPermission: notSupported,
  fetchWalletPlugins: notSupported,
};

export default solanaSdk;
