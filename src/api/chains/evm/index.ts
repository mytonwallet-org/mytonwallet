import type { EVMChain } from '../../types';
import type { ChainSdk } from '../../types/chains';
import { DappProtocolType } from '../../dappProtocols/types';

import { fetchActivityDetails, fetchActivitySlice, fetchCrossChainActivitySlice } from './activities';
import { normalizeAddress } from './address';
import {
  createSubWalletFromDerivation,
  fetchPrivateKeyString,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
  getWalletVariants,
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
import { checkTransactionDraft, sendSignedTransaction, submitGasfullTransfer } from './transfer';
import { getAddressInfo, getWalletBalance } from './wallet';

type OmitFirstArg<F extends (...args: any) => any> =
  Parameters<F> extends [any, ...infer Rest]
    ? (...args: Rest) => ReturnType<F>
    : never;

function notSupported(): never {
  throw new Error('Not supported in EVM');
}

class EVMChainSdk<T extends EVMChain> implements ChainSdk<T> {
  constructor(private readonly chain: T) {}

  #bindChain<F extends (chain: T, ...args: any[]) => any>(fn: F): OmitFirstArg<F> {
    return ((...args: any[]) => fn(this.chain, ...args)) as OmitFirstArg<F>;
  }

  getAddressInfo = this.#bindChain(getAddressInfo);
  fetchCrossChainActivitySlice = fetchCrossChainActivitySlice;
  fetchActivitySlice = this.#bindChain(fetchActivitySlice);
  fetchActivityDetails = fetchActivityDetails;

  decryptComment = notSupported;

  normalizeAddress = normalizeAddress;
  getWalletFromBip39Mnemonic = this.#bindChain(getWalletFromBip39Mnemonic);
  getWalletFromPrivateKey = getWalletFromPrivateKey;
  getWalletFromAddress = getWalletFromAddress;

  getWalletBalance = this.#bindChain(getWalletBalance);

  getWalletsFromLedgerAndLoadBalance = notSupported;

  getWalletVariants = this.#bindChain(getWalletVariants<T>);

  createSubWalletFromDerivation = this.#bindChain(createSubWalletFromDerivation<T>);

  setupActivePolling = this.#bindChain(setupActivePolling);
  setupInactivePolling = this.#bindChain(setupInactivePolling);

  fetchToken = notSupported;
  importToken = notSupported;

  checkTransactionDraft = this.#bindChain(checkTransactionDraft);

  fetchEstimateDiesel = notSupported;

  submitGasfullTransfer = this.#bindChain(submitGasfullTransfer);

  submitGaslessTransfer = notSupported;
  verifyLedgerWalletAddress = notSupported;

  fetchPrivateKeyString = this.#bindChain(fetchPrivateKeyString);

  getIsLedgerAppOpen = notSupported;

  fetchTransactionById = this.#bindChain(fetchTransactionById);

  dapp = {
    supportedProtocols: [DappProtocolType.WalletConnect],
    signDappData: this.#bindChain(signDappData),
    signDappTransfers: this.#bindChain(signDappTransfers),
    parseTransactionForPreview: this.#bindChain(parseTransactionForPreview),
    sendSignedTransaction: this.#bindChain(sendSignedTransaction),
  };

  getAccountNfts = this.#bindChain(getAccountNfts);
  streamAllAccountNfts = this.#bindChain(streamAllAccountNfts);
  checkNftTransferDraft = this.#bindChain(checkNftTransferDraft);
  submitNftTransfers = this.#bindChain(submitNftTransfers);
  checkNftOwnership = this.#bindChain(checkNftOwnership);
}

export default EVMChainSdk;
