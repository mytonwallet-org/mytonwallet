import type { ChainSdk } from '../../types/chains';
import { DappProtocolType } from '../../dappProtocols/types';

import { fetchNftByAddress } from './toncenter/nfts';
import { decryptComment, fetchActivityDetails, fetchActivitySlice } from './activities';
import { normalizeAddress } from './address';
import {
  fetchPrivateKeyString,
  generateMnemonic,
  getOtherVersionWallet,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromMnemonic,
  getWalletFromPrivateKey,
  getWalletsFromLedgerAndLoadBalance,
  validateMnemonic,
} from './auth';
import { TON_BIP39_PATH } from './constants';
import { signConnectionProof, signDappData, signDappTransfers } from './dapp';
import {
  checkDnsChangeWalletDraft,
  checkDnsRenewalDraft,
  submitDnsChangeWallet,
  submitDnsRenewal,
} from './domains';
import * as mfa from './mfa';
import {
  checkNftOwnership,
  checkNftTransferDraft,
  getAccountNfts,
  streamAllAccountNfts,
  submitNftTransfers,
} from './nfts';
import { getIsLedgerAppOpen } from './other';
import { setupActivePolling, setupInactivePolling } from './polling';
import * as staking from './staking';
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
  getDefaultDerivation: () => ({ path: TON_BIP39_PATH, index: 0 }),
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
  fetchNftByAddress,
  dns: {
    checkDnsRenewalDraft,
    submitDnsRenewal,
    checkDnsChangeWalletDraft,
    submitDnsChangeWallet,
  },
  nativeMnemonic: {
    generateMnemonic,
    validateMnemonic,
    getWalletFromMnemonic,
  },
  getOtherVersionWallet,
};

// Staking and MFA are wired only when extra features are on. A `NO_EXTRA_FEATURES` build leaves both modules and
// their contracts out through `plugins/disabledImports.ts`, which needs the flag read inline, as here.
if (process.env.NO_EXTRA_FEATURES !== '1') {
  tonSdk.staking = {
    checkStakeDraft: staking.checkStakeDraft,
    checkUnstakeDraft: staking.checkUnstakeDraft,
    submitStake: staking.submitStake,
    submitUnstake: staking.submitUnstake,
    submitTokenStakingClaim: staking.submitTokenStakingClaim,
    submitUnstakeEthenaLocked: staking.submitUnstakeEthenaLocked,
    getCommonData: staking.getStakingCommonData,
  };

  tonSdk.mfa = {
    installMfaExtension: mfa.installMfaExtension,
    createRemoveMfaExtensionPayload: mfa.createRemoveMfaExtensionPayload,
    resolveExtensionAddress: mfa.resolveExtensionAddress,
  };
}

export default tonSdk;

// The chain methods that haven't been multichain-refactored yet:

export {
  getKeyPairFromStoredMnemonic,
} from './auth';
export {
  BACKEND_AUTH_SIGN_MESSAGE,
  buildBackendAuthToken,
} from './backendAuth';
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
  insertMintlessPayload,
} from './tokens';
export {
  validateDexSwapTransfers,
} from './swap';
