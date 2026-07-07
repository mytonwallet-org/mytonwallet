import type { ChainSdk } from '../../types/chains';
import { DappProtocolType } from '../../dappProtocols/types';

import { decryptComment, fetchActivityDetails, fetchActivitySlice } from './activities';
import { normalizeAddress } from './address';
import {
  fetchPrivateKeyString,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
  getWalletsFromLedgerAndLoadBalance,
} from './auth';
import { signConnectionProof, signDappData, signDappTransfers } from './dapp';
import {
  checkNftOwnership,
  checkNftTransferDraft,
  getAccountNfts,
  streamAllAccountNfts,
  submitNftTransfers,
} from './nfts';
import { getIsLedgerAppOpen } from './other';
import { setupActivePolling, setupInactivePolling } from './polling';
import { buildOnchainSwapTransfer, submitOnchainSwapTransfer } from './swap';
import { fetchToken, importToken } from './tokens';
import { fetchTransactionById } from './transactionInfo';
import {
  checkToAddress,
  checkTransactionDraft,
  fetchEstimateDiesel,
  submitGasfullTransfer,
  submitGaslessTransfer,
} from './transfer';
import {
  fetchBalances,
  fetchWalletPlugins,
  getWalletBalance,
  verifyLedgerWalletAddress,
} from './wallet';

const notSupported = () => {
  throw new Error('Not supported in TON');
};

const tonSdk: ChainSdk<'ton'> = {
  fetchActivitySlice,
  crosschain: undefined,
  fetchActivityDetails,
  decryptComment,
  normalizeAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
  getWalletFromAddress,
  getWalletsFromLedgerAndLoadBalance,
  setupActivePolling,
  setupInactivePolling,
  fetchToken,
  importToken,
  checkTransactionDraft,
  fetchEstimateDiesel,
  submitGasfullTransfer,
  submitGaslessTransfer,
  buildOnchainSwapTransfer,
  submitOnchainSwapTransfer,
  getAddressInfo: checkToAddress,
  getWalletBalance,
  getWalletAssets: fetchBalances,
  verifyLedgerWalletAddress,
  fetchPrivateKeyString,
  getIsLedgerAppOpen,
  fetchTransactionById,
  dapp: {
    supportedProtocols: [DappProtocolType.TonConnect],
    signConnectionProof,
    signDappTransfers,
    signDappData,
  },
  getAccountNfts,
  streamAllAccountNfts,
  checkNftTransferDraft,
  submitNftTransfers,
  checkNftOwnership,
  fetchWalletPermissions: notSupported,
  revokeWalletPermission: notSupported,
  fetchWalletPlugins,
};

export default tonSdk;

// The chain methods that haven't been multichain-refactored yet:

export {
  generateMnemonic,
  rawSign,
  validateMnemonic,
  getWalletFromMnemonic,
  getOtherVersionWallet,
} from './auth';
export {
  submitDnsRenewal,
  checkDnsRenewalDraft,
  checkDnsChangeWalletDraft,
  submitDnsChangeWallet,
} from './domains';
export {
  checkTransactionDraft,
  submitGasfullTransfer,
  checkMultiTransactionDraft,
  submitMultiTransfer,
  submitMultiTransferWithMfa,
  signTransfers,
} from './transfer';
export {
  getWalletBalance,
  pickWalletByAddress,
} from './wallet';
export {
  checkStakeDraft,
  checkUnstakeDraft,
  submitTokenStakingClaim,
  submitStake,
  submitUnstake,
  getStakingStates,
  getBackendStakingState,
  submitUnstakeEthenaLocked,
} from './staking';
export {
  insertMintlessPayload,
} from './tokens';
export {
  validateDexSwapTransfers,
} from './swap';
