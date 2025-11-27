import type { ChainSdk } from '../../types/chains';

import { decryptComment, fetchActivityDetails, fetchActivitySlice } from './activities';
import { normalizeAddress } from './address';
import { getWalletFromAddress, getWalletFromBip39Mnemonic, getWalletsFromLedgerAndLoadBalance } from './auth';
import { getIsLedgerAppOpen } from './other';
import { setupActivePolling, setupInactivePolling } from './polling';
import { fetchToken, importToken } from './tokens';
import {
  checkToAddress,
  checkTransactionDraft,
  fetchEstimateDiesel,
  submitGasfullTransfer,
  submitGaslessTransfer,
} from './transfer';
import { verifyLedgerWalletAddress } from './wallet';

const tonSdk: ChainSdk<'ton'> = {
  fetchActivitySlice,
  fetchActivityDetails,
  decryptComment,
  normalizeAddress,
  getWalletFromBip39Mnemonic,
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
  getAddressInfo: checkToAddress,
  verifyLedgerWalletAddress,
  getIsLedgerAppOpen,
};

export default tonSdk;

// The chain methods that haven't been multichain-refactored yet:

export {
  generateMnemonic,
  rawSign,
  validateMnemonic,
  fetchPrivateKey,
  getWalletFromMnemonic,
  getWalletFromPrivateKey,
  getOtherVersionWallet,
} from './auth';
export {
  getAccountNfts,
  checkNftTransferDraft,
  submitNftTransfers,
  checkNftOwnership,
} from './nfts';
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
