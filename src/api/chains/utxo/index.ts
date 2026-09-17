import type { ApiNetwork, UTXOChain } from '../../types';
import type { ChainSdk } from '../../types/chains';

import { fetchActivityDetails, fetchActivitySlice } from './activities';
import { normalizeAddress as normalizeUtxoAddress } from './address';
import {
  fetchPrivateKeyString,
  getWalletFromAddress,
  getWalletFromBip39Mnemonic,
  getWalletFromPrivateKey,
} from './auth';
import { getDefaultUtxoAddressType, getDefaultUtxoDerivationPath } from './constants';
import { setupActivePolling, setupInactivePolling } from './polling';
import { fetchTransactionById } from './transactionInfo';
import { checkTransactionDraft, fetchEstimateDiesel, submitGasfullTransfer } from './transfer';
import { fetchAccountAssets, getAddressInfo, getWalletBalance } from './wallet';

type OmitFirstArg<F extends (...args: any) => any> =
  Parameters<F> extends [any, ...infer Rest]
    ? (...args: Rest) => ReturnType<F>
    : never;

function notSupported(): never {
  throw new Error('Not supported in UTXO');
}

class UTXOChainSdk<T extends UTXOChain> implements ChainSdk<T> {
  constructor(private readonly chain: T) {}

  #bindChain<F extends (chain: T, ...args: any[]) => any>(fn: F): OmitFirstArg<F> {
    return ((...args: any[]) => fn(this.chain, ...args)) as OmitFirstArg<F>;
  }

  crosschain = undefined;

  getAddressInfo = this.#bindChain(getAddressInfo);

  fetchActivitySlice = this.#bindChain(fetchActivitySlice);
  fetchActivityDetails = this.#bindChain(fetchActivityDetails);

  decryptComment = notSupported;

  normalizeAddress = (address: string, network?: ApiNetwork) => (
    normalizeUtxoAddress(this.chain, address, network)
  );

  getDefaultDerivation = () => ({
    path: getDefaultUtxoDerivationPath(this.chain),
    index: 0,
    label: getDefaultUtxoAddressType(this.chain),
  });

  getWalletFromBip39Mnemonic = this.#bindChain(getWalletFromBip39Mnemonic);
  getWalletFromPrivateKey = this.#bindChain(getWalletFromPrivateKey);
  getWalletFromAddress = this.#bindChain(getWalletFromAddress);

  getWalletBalance = this.#bindChain(getWalletBalance);
  getWalletAssets = this.#bindChain(fetchAccountAssets);

  getWalletsFromLedgerAndLoadBalance = notSupported;

  setupActivePolling = this.#bindChain(setupActivePolling);
  setupInactivePolling = this.#bindChain(setupInactivePolling);

  fetchToken = notSupported;
  importToken = notSupported;

  checkTransactionDraft = this.#bindChain(checkTransactionDraft);

  fetchEstimateDiesel = fetchEstimateDiesel;

  submitGasfullTransfer = this.#bindChain(submitGasfullTransfer);

  submitGaslessTransfer = notSupported;
  verifyLedgerWalletAddress = notSupported;

  buildOnchainSwapTransfer = notSupported;
  submitOnchainSwapTransfer = notSupported;

  fetchPrivateKeyString = this.#bindChain(fetchPrivateKeyString);

  getIsLedgerAppOpen = notSupported;

  fetchTransactionById = this.#bindChain(fetchTransactionById);

  dapp = undefined;

  getAccountNfts = notSupported;
  streamAllAccountNfts = notSupported;
  checkNftTransferDraft = notSupported;
  submitNftTransfers = notSupported;
  checkNftOwnership = notSupported;

  fetchWalletPermissions = notSupported;
  revokeWalletPermission = notSupported;
  fetchWalletPlugins = notSupported;
}

export default UTXOChainSdk;
