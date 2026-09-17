import { selectUTXO } from '@scure/btc-signer';

import type {
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiNetwork,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  UTXOChain,
} from '../../types';
import type { UtxoListItem } from './types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { explainApiTransferFee } from '../../../util/fee/transferFee';
import { fetchJson } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { getNativeToken } from '../../../util/tokens';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { DIESEL_NOT_AVAILABLE } from '../../common/other';
import { handleServerError } from '../../errors';
import { isValidAddress, normalizeAddress, toUtxoSignerAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import {
  DOGECOIN_DEFAULT_FEE_RATE_SAT_VB,
  UTXO_DEFAULT_FEE_RATE_SAT_VB,
  UTXO_RPC_URLS,
  type UtxoAddressType,
} from './constants';
import { getUtxoSignerNetwork } from './network';
import { getUtxoLockingScripts, resolveAddressType } from './payment';
import { signBitcoinCashTransaction } from './signBitcoinCash';
import {
  fetchSpendableUtxos as fetchSpendableUtxoList,
  getSpendableBalance,
} from './utxos';

const UTXO_SELECTION_STRATEGY = 'default';

function getSelectUtxoOptions(
  chain: UTXOChain,
  network: ApiNetwork,
  feeRate: bigint,
  changeAddress: string,
  addressType: UtxoAddressType,
  createTx: boolean,
) {
  return {
    feePerByte: feeRate,
    changeAddress: toUtxoSignerAddress(chain, network, changeAddress),
    network: getUtxoSignerNetwork(chain, network),
    createTx,
    allowLegacyWitnessUtxo: addressType === 'legacy',
  };
}

export async function checkTransactionDraft(
  chain: UTXOChain,
  options: ApiCheckTransactionDraftOptions,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress, payload,
  } = options;
  const { network } = parseAccountId(accountId);

  if (payload) {
    throw new Error(`Transfer payload is not supported in ${chain}`);
  }

  if (tokenAddress) {
    return { error: ApiTransactionDraftError.InvalidToAddress };
  }

  const result: ApiCheckTransactionDraftResult = {};

  try {
    if (!isValidAddress(chain, network, toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    result.resolvedAddress = normalizeAddress(chain, toAddress, network);

    const { address, publicKey, derivation } = await fetchStoredWallet(accountId, chain);
    const addressType = resolveAddressType(address, derivation);

    const transferAmount = amount ?? 0n;

    const { fee, spendableBalance } = await estimateTransferFee(
      chain,
      network,
      address,
      publicKey ?? '',
      toAddress,
      transferAmount,
      addressType,
    );

    const tokenSlug = getNativeToken(chain).slug;

    if (fee !== undefined) {
      result.explainedFee = explainApiTransferFee({
        fee,
        realFee: fee,
        tokenSlug,
      });
    }

    const isFullBalanceTransfer = transferAmount > 0n && transferAmount >= spendableBalance;
    const isEnoughBalance = fee !== undefined && (
      isFullBalanceTransfer
        ? spendableBalance > fee
        : spendableBalance >= transferAmount + fee
    );

    if (!isEnoughBalance) {
      result.error = ApiTransactionDraftError.InsufficientBalance;
    }

    return result;
  } catch (err) {
    logDebugError(`utxo:${chain}:checkTransactionDraft`, err);

    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

export async function submitGasfullTransfer(
  chain: UTXOChain,
  options: ApiSubmitGasfullTransferOptions,
): Promise<ApiSubmitGasfullTransferResult | { error: string }> {
  const {
    accountId, enclaveToken = '', toAddress, amount, fee = 0n, tokenAddress, payload, noFeeCheck,
  } = options;

  const { network } = parseAccountId(accountId);

  if (payload || tokenAddress) {
    throw new Error(`Token transfers are not supported in ${chain}`);
  }

  try {
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address, publicKey, derivation } = account.byChain[chain];

    if (!publicKey) {
      return { error: ApiCommonError.Unexpected };
    }

    const addressType = resolveAddressType(address, derivation);
    const spendable = await fetchSpendableUtxos(chain, network, address, publicKey, addressType);
    const spendableBalance = getSpendableBalance(spendable.sourceUtxos);
    const isFullBalanceTransfer = amount > 0n && amount >= spendableBalance;
    let transferAmount = amount;

    if (isFullBalanceTransfer) {
      const feeRate = await fetchFeeRate(network, chain);
      const maxTransfer = selectMaxTransferAmount(
        chain,
        network,
        address,
        toAddress,
        addressType,
        feeRate,
        spendable.inputs,
        spendableBalance,
      );

      if (!maxTransfer) {
        return { error: ApiTransactionError.InsufficientBalance };
      }

      transferAmount = maxTransfer.amount;
    } else if (!noFeeCheck && spendableBalance < amount + fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.Unexpected };
    }

    const signer = getSignerFromPrivateKey(network, privateKey);

    const built = await buildSignedTransfer({
      network,
      chain,
      fromAddress: address,
      toAddress,
      amount: transferAmount,
      signer,
      addressType,
      inputs: spendable.inputs,
      useAllInputs: isFullBalanceTransfer,
    });

    if (!built) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const { tx, fee: actualFee } = built;

    if (!noFeeCheck && fee > 0n && actualFee > fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const endpoint = UTXO_RPC_URLS[network](chain);

    const response = await fetchJson<{ result?: string; error?: { message?: string } }>(
      `${endpoint}/api/v2/sendtx/`,
      undefined,
      {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: tx.hex,
      },
    );

    if (response.error || !response.result) {
      throw new Error(response.error?.message ?? 'UTXO broadcast failed');
    }

    return { txId: response.result };
  } catch (err) {
    logDebugError(`utxo:${chain}:submitGasfullTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export function fetchEstimateDiesel(_accountId: string, _tokenAddress: string) {
  return DIESEL_NOT_AVAILABLE;
}

async function fetchSpendableUtxos(
  chain: UTXOChain,
  network: ApiNetwork,
  address: string,
  publicKeyHex: string,
  addressType: UtxoAddressType,
) {
  const spendable = await fetchSpendableUtxoList(chain, network, address);
  const lockingScripts = getUtxoLockingScripts(chain, network, publicKeyHex, addressType);

  return {
    sourceUtxos: spendable,
    inputs: spendable.map((utxo) => mapUtxoToInput(utxo, lockingScripts)),
  };
}

function mapUtxoToInput(
  utxo: UtxoListItem,
  lockingScripts: ReturnType<typeof getUtxoLockingScripts>,
) {
  // Blockbook returns display-order txids; @scure/btc-signer expects the same format
  // and writes the internal (wire) hash to the serialized transaction.
  return {
    txid: utxo.txid,
    index: utxo.vout,
    witnessUtxo: {
      amount: BigInt(utxo.value),
      script: lockingScripts.script,
    },
    ...(lockingScripts.redeemScript && { redeemScript: lockingScripts.redeemScript }),
    ...(lockingScripts.tapInternalKey && { tapInternalKey: lockingScripts.tapInternalKey }),
  };
}

function selectMaxTransferAmount(
  chain: UTXOChain,
  network: ApiNetwork,
  fromAddress: string,
  toAddress: string,
  addressType: UtxoAddressType,
  feeRate: bigint,
  inputs: ReturnType<typeof mapUtxoToInput>[],
  spendableBalance: bigint,
) {
  const signerToAddress = toUtxoSignerAddress(chain, network, toAddress);
  const selectOptions = getSelectUtxoOptions(chain, network, feeRate, fromAddress, addressType, false);

  let recipientAmount = spendableBalance;

  while (recipientAmount > 0n) {
    const selected = selectUTXO(
      inputs,
      [{ address: signerToAddress, amount: recipientAmount }],
      'all',
      selectOptions,
    );

    if (!selected?.fee) {
      return undefined;
    }

    const nextAmount = spendableBalance - selected.fee;
    if (nextAmount <= 0n) {
      return undefined;
    }

    if (nextAmount === recipientAmount) {
      return { amount: nextAmount, fee: selected.fee };
    }

    recipientAmount = nextAmount;
  }

  return undefined;
}

async function estimateTransferFee(
  chain: UTXOChain,
  network: ApiNetwork,
  fromAddress: string,
  publicKeyHex: string,
  toAddress: string,
  amount: bigint,
  addressType: UtxoAddressType,
) {
  const { inputs, sourceUtxos } = await fetchSpendableUtxos(
    chain, network, fromAddress, publicKeyHex, addressType,
  );
  const spendableBalance = getSpendableBalance(sourceUtxos);
  const feeRate = await fetchFeeRate(network, chain);

  if (amount >= spendableBalance && spendableBalance > 0n) {
    const maxTransfer = selectMaxTransferAmount(
      chain, network, fromAddress, toAddress, addressType, feeRate, inputs, spendableBalance,
    );

    if (!maxTransfer) {
      return { spendableBalance };
    }

    return {
      fee: maxTransfer.fee,
      spendableBalance,
    };
  }

  const signerToAddress = toUtxoSignerAddress(chain, network, toAddress);
  const selectOptions = getSelectUtxoOptions(chain, network, feeRate, fromAddress, addressType, false);
  const select = (strategy: typeof UTXO_SELECTION_STRATEGY | 'all', outputAmount: bigint) => selectUTXO(
    inputs,
    [{ address: signerToAddress, amount: outputAmount }],
    strategy,
    selectOptions,
  );

  const selected = select(UTXO_SELECTION_STRATEGY, amount);
  if (selected) {
    return { fee: selected.fee ?? feeRate * 250n, spendableBalance };
  }

  // The sweep fee lets the UI derive `balance - fee` as the maximum, but only when that amount re-estimates at the same fee
  const sweepFee = select('all', amount)?.fee;
  const maxAmount = sweepFee === undefined ? 0n : spendableBalance - sweepFee;
  if (maxAmount <= 0n || select(UTXO_SELECTION_STRATEGY, maxAmount)?.fee !== sweepFee) {
    return { spendableBalance };
  }

  return { fee: sweepFee, spendableBalance };
}

async function buildSignedTransfer(options: {
  network: ApiNetwork;
  chain: UTXOChain;
  fromAddress: string;
  toAddress: string;
  amount: bigint;
  signer: Uint8Array;
  addressType: UtxoAddressType;
  inputs: ReturnType<typeof mapUtxoToInput>[];
  useAllInputs?: boolean;
}) {
  const {
    network, chain, fromAddress, toAddress, amount, signer, addressType, inputs, useAllInputs,
  } = options;

  const feeRate = await fetchFeeRate(network, chain);

  const signerToAddress = toUtxoSignerAddress(chain, network, toAddress);
  const selected = selectUTXO(
    inputs,
    [{ address: signerToAddress, amount }],
    useAllInputs ? 'all' : UTXO_SELECTION_STRATEGY,
    getSelectUtxoOptions(chain, network, feeRate, fromAddress, addressType, true),
  );

  if (!selected?.tx) {
    return undefined;
  }

  if (chain === 'bitcoincash') {
    signBitcoinCashTransaction(selected.tx, signer);
  } else {
    selected.tx.sign(signer);
  }

  selected.tx.finalize();

  return {
    tx: selected.tx,
    fee: selected.fee ?? 0n,
  };
}

async function fetchFeeRate(network: ApiNetwork, chain: UTXOChain) {
  try {
    const response = await fetchJson<{ result: string | number }>(
      `${UTXO_RPC_URLS[network](chain)}/api/v2/estimatefee/1`,
    );
    const coinPerKb = Number(response.result);

    if (Number.isFinite(coinPerKb) && coinPerKb > 0) {
      return BigInt(Math.max(1, Math.ceil((coinPerKb * 1e8) / 1000)));
    }
  } catch (err) {
    logDebugError(`utxo:${chain}:fetchFeeRate`, err);
  }

  return chain === 'dogecoin'
    ? DOGECOIN_DEFAULT_FEE_RATE_SAT_VB
    : UTXO_DEFAULT_FEE_RATE_SAT_VB;
}
