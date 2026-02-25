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
import { fetchTransactionById } from './transactionInfo';
import { checkTransactionDraft, fetchEstimateDiesel, sendSignedTransaction, submitGasfullTransfer } from './transfer';
import { getAddressInfo } from './wallet';

function notSupported(): never {
  throw new Error('Not supported in Solana');
}

const solanaSdk: ChainSdk<'solana'> = {
  fetchActivitySlice,
  fetchActivityDetails,
  decryptComment: notSupported,
  normalizeAddress,
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
  submitGaslessTransfer: notSupported,
  getAddressInfo,
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
};

export default solanaSdk;
