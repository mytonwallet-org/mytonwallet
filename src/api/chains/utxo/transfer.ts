import { selectUTXO, type Transaction } from '@scure/btc-signer';

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
import { bytesToHexLower, signZcashTransaction } from './signZcash';
import {
  fetchSpendableUtxos as fetchSpendableUtxoList,
  getSpendableBalance,
} from './utxos';
import {
  getZcashConsensusBranchIdForHeight,
  parseZcashConsensusBranchIdHex,
} from './zcashConsensusBranchId';
import {
  bumpZcashFeePerByteForZip317,
  estimateZcashConventionalFee,
  resolveZcashFeePerByte,
} from './zcashZip317';

const UTXO_SELECTION_STRATEGY = 'default';

const ZCASH_TRANSFER_OUTPUT_COUNT = 2;

const ZCASH_SWEEP_OUTPUT_COUNT = 1;

function getWireTransferFee(tx: Transaction, reportedFee?: bigint) {
  if (reportedFee !== undefined && reportedFee > 0n) {
    return reportedFee;
  }

  let inputTotal = 0n;
  let outputTotal = 0n;

  for (let i = 0; i < tx.inputsLength; i++) {
    inputTotal += tx.getInput(i).witnessUtxo?.amount ?? 0n;
  }

  for (let i = 0; i < tx.outputsLength; i++) {
    outputTotal += tx.getOutput(i).amount ?? 0n;
  }

  return inputTotal - outputTotal;
}

function getSelectUtxoOptions(
  chain: UTXOChain,
  network: ApiNetwork,
  feeRate: bigint,
  changeAddress: string,
  addressType: UtxoAddressType,
  createTx: boolean,
  inputCount?: number,
  zcashOutputCount = ZCASH_TRANSFER_OUTPUT_COUNT,
) {
  const feePerByte = chain === 'zcash' && inputCount !== undefined
    ? resolveZcashFeePerByte(feeRate, inputCount, zcashOutputCount)
    : feeRate;

  return {
    feePerByte,
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

    const isFullBalanceTransfer = transferAmount > 0n && (
      transferAmount >= spendableBalance
      || (fee !== undefined && transferAmount + fee >= spendableBalance)
    );
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

    const isFullBalanceTransfer = amount > 0n && (
      amount >= spendableBalance
      || (maxTransfer !== undefined && amount >= maxTransfer.amount)
      || (fee > 0n && amount + fee >= spendableBalance)
    );
    let transferAmount = amount;

    if (isFullBalanceTransfer) {
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
      zcashSigning: chain === 'zcash' ? await fetchZcashSigningParams(network, chain) : undefined,
    });

    if (!built) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const { tx, rawTxHex, fee: actualFee } = built;

    // Quoted fee (e.g. swap buildTransaction) may use a lighter estimate than createTx signing.
    if (!noFeeCheck && !isFullBalanceTransfer && spendableBalance < transferAmount + actualFee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const endpoint = UTXO_RPC_URLS[network](chain);
    const broadcastPayload = rawTxHex ?? tx?.hex;

    if (!broadcastPayload) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const response = await fetchJson<{ result?: string; error?: { message?: string } }>(
      `${endpoint}/api/v2/sendtx/`,
      undefined,
      {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: broadcastPayload,
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
  // Blockbook returns display-order txids; @scure/btc-signer expects the same format.
  // Zcash v5 serialization reverses prevout hashes in signZcash (same wire order as Bitcoin).
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
  const selectOptions = getSelectUtxoOptions(
    chain, network, feeRate, fromAddress, addressType, true, inputs.length, ZCASH_SWEEP_OUTPUT_COUNT,
  );
  const zcashSweepMinFee = chain === 'zcash'
    ? estimateZcashConventionalFee(inputs.length, ZCASH_SWEEP_OUTPUT_COUNT)
    : 0n;

  let recipientAmount = spendableBalance;

  while (recipientAmount > 0n) {
    const selected = selectUTXO(
      inputs,
      [{ address: signerToAddress, amount: recipientAmount }],
      'all',
      selectOptions,
    );

    if (selected?.fee === undefined) {
      return undefined;
    }

    const selectedFee = chain === 'zcash' && selected.fee < zcashSweepMinFee
      ? zcashSweepMinFee
      : selected.fee;

    const nextAmount = spendableBalance - selectedFee;
    if (nextAmount <= 0n) {
      return undefined;
    }

    if (nextAmount === recipientAmount) {
      return { amount: nextAmount, fee: selectedFee };
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
  const selectOptions = getSelectUtxoOptions(
    chain, network, feeRate, fromAddress, addressType, true, inputs.length,
  );
  const select = (strategy: typeof UTXO_SELECTION_STRATEGY | 'all', outputAmount: bigint) => selectUTXO(
    inputs,
    [{ address: signerToAddress, amount: outputAmount }],
    strategy,
    selectOptions,
  );

  const maxTransfer = spendableBalance > 0n
    ? selectMaxTransferAmount(
      chain, network, fromAddress, toAddress, addressType, feeRate, inputs, spendableBalance,
    )
    : undefined;

  const selected = select(UTXO_SELECTION_STRATEGY, amount);
  if (selected) {
    const partialFee = selected.fee ?? feeRate * 250n;

    if (maxTransfer && amount >= maxTransfer.amount) {
      return { fee: maxTransfer.fee, spendableBalance };
    }

    if (amount + partialFee >= spendableBalance && maxTransfer) {
      return { fee: maxTransfer.fee, spendableBalance };
    }

    return { fee: partialFee, spendableBalance };
  }

  // The sweep fee lets the UI derive `balance - fee` as the maximum, but only when that amount re-estimates at the same fee
  const sweepFee = select('all', amount)?.fee;
  const maxAmount = sweepFee === undefined ? 0n : spendableBalance - sweepFee;
  if (maxAmount <= 0n || select(UTXO_SELECTION_STRATEGY, maxAmount)?.fee !== sweepFee) {
    return { spendableBalance };
  }

  return { fee: maxTransfer?.fee ?? sweepFee, spendableBalance };
}

type ZcashSigningParams = {
  expiryHeight: number;
  consensusBranchId: number;
};

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
  zcashSigning?: ZcashSigningParams;
}) {
  const {
    network, chain, fromAddress, toAddress, amount, signer, addressType, inputs, useAllInputs, zcashSigning,
  } = options;

  const feeRate = await fetchFeeRate(network, chain);

  const signerToAddress = toUtxoSignerAddress(chain, network, toAddress);
  const zcashOutputCount = useAllInputs ? ZCASH_SWEEP_OUTPUT_COUNT : ZCASH_TRANSFER_OUTPUT_COUNT;
  let recipientAmount = amount;

  let selected = selectUTXO(
    inputs,
    [{ address: signerToAddress, amount: recipientAmount }],
    useAllInputs ? 'all' : UTXO_SELECTION_STRATEGY,
    getSelectUtxoOptions(
      chain, network, feeRate, fromAddress, addressType, true, inputs.length, zcashOutputCount,
    ),
  );

  if (chain === 'zcash' && selected?.tx) {
    let feePerByte = getSelectUtxoOptions(
      chain, network, feeRate, fromAddress, addressType, true, inputs.length, zcashOutputCount,
    ).feePerByte;

    for (let attempt = 0; attempt < 8 && selected?.tx; attempt++) {
      const zip317MinFee = estimateZcashConventionalFee(selected.tx.inputsLength, selected.tx.outputsLength);
      const selectedFee = getWireTransferFee(selected.tx, selected.fee);

      if (selectedFee >= zip317MinFee) {
        break;
      }

      if (useAllInputs) {
        let inputTotal = 0n;
        for (let i = 0; i < inputs.length; i++) {
          inputTotal += inputs[i].witnessUtxo.amount;
        }

        recipientAmount = inputTotal - zip317MinFee;
        if (recipientAmount <= 0n) {
          selected = undefined;
          break;
        }
      } else {
        feePerByte = bumpZcashFeePerByteForZip317(feePerByte, selectedFee, zip317MinFee);
      }

      selected = selectUTXO(
        inputs,
        [{ address: signerToAddress, amount: recipientAmount }],
        useAllInputs ? 'all' : UTXO_SELECTION_STRATEGY,
        {
          ...getSelectUtxoOptions(
            chain,
            network,
            feePerByte,
            fromAddress,
            addressType,
            true,
            selected.tx.inputsLength,
            useAllInputs ? ZCASH_SWEEP_OUTPUT_COUNT : selected.tx.outputsLength,
          ),
          feePerByte,
        },
      );
    }
  }

  if (!selected?.tx) {
    return undefined;
  }

  if (chain === 'bitcoincash') {
    signBitcoinCashTransaction(selected.tx, signer);
    selected.tx.finalize();

    return {
      tx: selected.tx,
      fee: selected.fee ?? 0n,
    };
  }

  if (chain === 'zcash') {
    if (!zcashSigning) {
      throw new Error('Zcash transfer requires signing parameters');
    }

    const { expiryHeight, consensusBranchId } = zcashSigning;
    const rawTx = signZcashTransaction(selected.tx, network, signer, expiryHeight, consensusBranchId);

    return {
      rawTxHex: bytesToHexLower(rawTx),
      fee: getWireTransferFee(selected.tx, selected.fee),
    };
  }

  selected.tx.sign(signer);
  selected.tx.finalize();

  return {
    tx: selected.tx,
    fee: getWireTransferFee(selected.tx, selected.fee),
  };
}

async function fetchZcashSigningParams(
  network: ApiNetwork,
  chain: UTXOChain,
): Promise<ZcashSigningParams | undefined> {
  try {
    const info = await fetchJson<{
      blockbook?: { bestHeight?: number };
      backend?: { blocks?: number; consensus?: { chaintip?: string; nextblock?: string } };
    }>(
      `${UTXO_RPC_URLS[network](chain)}/api/v2/status`,
    );
    const bestHeight = info.blockbook?.bestHeight ?? info.backend?.blocks;
    const consensusBranchId = parseZcashConsensusBranchIdHex(info.backend?.consensus?.chaintip)
      ?? parseZcashConsensusBranchIdHex(info.backend?.consensus?.nextblock)
      ?? (typeof bestHeight === 'number' && bestHeight > 0
        ? getZcashConsensusBranchIdForHeight(network, bestHeight)
        : undefined);

    if (typeof bestHeight === 'number' && bestHeight > 0 && consensusBranchId !== undefined) {
      return {
        expiryHeight: bestHeight + 40,
        consensusBranchId,
      };
    }
  } catch (err) {
    logDebugError(`utxo:${chain}:fetchZcashSigningParams`, err);
  }

  return undefined;
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
