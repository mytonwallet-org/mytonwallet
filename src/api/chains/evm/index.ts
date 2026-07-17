import type { EVMChain } from '../../types';
import type { ChainSdk } from '../../types/chains';
import { DappProtocolType } from '../../dappProtocols/types';

import { fetchActivityDetails, fetchActivitySlice, fetchCrossChainActivitySlice } from './activities';
import { normalizeAddress } from './address';
import { fetchEvmWalletPermissions, revokeEvmWalletPermission } from './approvals';
import {
  createSubWalletFromDerivation,
  fetchPrivateKeyString,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
} from './auth';
import { EVM_DERIVATION_PATHS } from './constants';
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
import { fetchAccountAssets, fetchCrosschainAccountAssets, getAddressInfo, getWalletBalance } from './wallet';

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

  crosschain = {
    fetchCrossChainActivitySlice,
    fetchCrosschainAccountAssets,
  };

  fetchActivitySlice = this.#bindChain(fetchActivitySlice);
  fetchActivityDetails = fetchActivityDetails;

  decryptComment = notSupported;

  normalizeAddress = normalizeAddress;
  getDefaultDerivation = () => ({ path: EVM_DERIVATION_PATHS.default, index: 0, label: 'default' });
  getWalletFromBip39Mnemonic = this.#bindChain(getWalletFromBip39Mnemonic);
  getWalletFromPrivateKey = getWalletFromPrivateKey;
  getWalletFromAddress = getWalletFromAddress;

  getWalletBalance = this.#bindChain(getWalletBalance);
  getWalletAssets = this.#bindChain(fetchAccountAssets);

  getWalletsFromLedgerAndLoadBalance = notSupported;

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

  buildOnchainSwapTransfer = notSupported;
  submitOnchainSwapTransfer = notSupported;

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

  fetchWalletPermissions = this.#bindChain(fetchEvmWalletPermissions);

  revokeWalletPermission = this.#bindChain(revokeEvmWalletPermission);

  fetchWalletPlugins = notSupported;
}

export default EVMChainSdk;
