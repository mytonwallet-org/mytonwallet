import type { ChainSdk } from '../../types/chains';

import { decryptComment, fetchActivityDetails, fetchActivitySlice } from './activities';
import { getWalletFromAddress, getWalletFromBip39Mnemonic, getWalletsFromLedgerAndLoadBalance } from './auth';
import { getIsLedgerAppOpen } from './other';
import { setupActivePolling, setupInactivePolling } from './polling';
import { checkTransactionDraft, submitTransfer } from './transfer';
import { verifyLedgerWalletAddress } from './wallet';

const tonSdk: ChainSdk<'ton'> = {
  fetchActivitySlice,
  fetchActivityDetails,
  decryptComment,
  getWalletFromBip39Mnemonic,
  getWalletFromAddress,
  getWalletsFromLedgerAndLoadBalance,
  setupActivePolling,
  setupInactivePolling,
  checkTransactionDraft,
  submitTransfer,
  verifyLedgerWalletAddress,
  getIsLedgerAppOpen,
};

export default tonSdk;

// The chain methods that haven't been multichain-refactored yet:

// todo: Remove as a part of the multichain send refactoring
export { submitTransfer };

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
  checkMultiTransactionDraft,
  checkToAddress,
  submitMultiTransfer,
  signTransfers,
  submitTransferWithDiesel,
  fetchEstimateDiesel,
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
  fetchToken,
  insertMintlessPayload,
} from './tokens';
export {
  normalizeAddress,
} from './address';
export {
  validateDexSwapTransfers,
} from './swap';
