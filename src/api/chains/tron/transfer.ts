// Importing from `tronweb/lib/commonjs/types` breaks eslint (eslint doesn't like any of import placement options)
// eslint-disable-next-line simple-import-sort/imports
import type { TronWeb } from 'tronweb';

import type { ApiSubmitTransferOptions, CheckTransactionDraftOptions } from '../../methods/types';
import type { ApiCheckTransactionDraftResult } from '../ton/types';
import { ApiTransactionDraftError, ApiTransactionError } from '../../types';
import type { ApiNetwork } from '../../types';

import { parseAccountId } from '../../../util/account';
import { logDebugError } from '../../../util/logs';
import { getChainParameters, getTronClient } from './util/tronweb';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { getMnemonic } from '../../common/mnemonic';
import { handleServerError } from '../../errors';
import { getTrc20Balance, getWalletBalance } from './wallet';
import type { ApiSubmitTransferTronResult } from './types';
import { hexToString } from '../../../util/stringFormat';
import { ONE_TRX, TRON_GAS } from './constants';

const SIGNATURE_SIZE = 65;

export async function checkTransactionDraft(
  options: CheckTransactionDraftOptions,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress,
  } = options;
  const { network } = parseAccountId(accountId);

  const tronWeb = getTronClient(network);
  const result: ApiCheckTransactionDraftResult = {};

  try {
    if (!tronWeb.isAddress(toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    result.resolvedAddress = toAddress;

    const { address } = await fetchStoredWallet(accountId, 'tron');
    const [trxBalance, bandwidth, { energyUnitFee, bandwidthUnitFee }] = await Promise.all([
      getWalletBalance(network, address),
      tronWeb.trx.getBandwidth(address),
      getChainParameters(network),
    ]);

    let fee: bigint;

    if (tokenAddress) {
      fee = await estimateTrc20TransferFee(tronWeb, {
        network,
        toAddress,
        tokenAddress,
        amount,
        energyUnitFee,
        fromAddress: address,
      });
    } else {
      // This call throws "Error: Invalid amount provided" when the amount is 0.
      // It doesn't throw when the amount is > than the balance.
      const [transaction, account] = await Promise.all([
        tronWeb.transactionBuilder.sendTrx(toAddress, Number(amount ?? 1), address),
        tronWeb.trx.getAccount(toAddress),
      ]);

      const size = 9 + 60 + Buffer.from(transaction.raw_data_hex, 'hex').byteLength + SIGNATURE_SIZE;
      fee = bandwidth > size ? 0n : BigInt(size) * BigInt(bandwidthUnitFee);

      // If the account is not activated, we pay an extra 1 TRX for activation
      if (account.balance === undefined) {
        fee += ONE_TRX;
      }
    }

    result.fee = fee;
    result.realFee = fee;

    const trxAmount = tokenAddress ? fee : (amount ?? 0n) + fee;
    const isEnoughTrx = trxBalance >= trxAmount;

    if (!isEnoughTrx) {
      result.error = ApiTransactionDraftError.InsufficientBalance;
    }

    // todo: Check that the amount ≤ the token balance (in case of a token transfer)

    return result;
  } catch (err) {
    logDebugError('tron:checkTransactionDraft', err);
    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

export async function submitTransfer(options: ApiSubmitTransferOptions): Promise<ApiSubmitTransferTronResult> {
  const {
    accountId, password = '', toAddress, amount, fee = 0n, tokenAddress,
  } = options;

  const { network } = parseAccountId(accountId);

  try {
    const tronWeb = getTronClient(network);

    const account = await fetchStoredChainAccount(accountId, 'tron');
    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain.tron;
    const trxBalance = await getWalletBalance(network, address);

    const trxAmount = tokenAddress ? fee : fee + amount;
    const isEnoughTrx = trxBalance >= trxAmount;

    if (!isEnoughTrx) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    // todo: Check that the amount ≤ the token balance (in case of a token transfer)

    const mnemonic = await getMnemonic(accountId, password, account);
    const privateKey = tronWeb.fromMnemonic(mnemonic!.join(' ')).privateKey.slice(2);

    if (tokenAddress) {
      const { transaction } = await buildTrc20Transfer(tronWeb, {
        toAddress, tokenAddress, amount, feeLimit: fee, fromAddress: address,
      });

      const signedTx = await tronWeb.trx.sign(transaction, privateKey);
      const result = await tronWeb.trx.sendRawTransaction(signedTx);

      return { amount, toAddress, txId: result.transaction.txID };
    } else {
      const result = await tronWeb.trx.sendTransaction(toAddress, Number(amount), {
        privateKey,
      });

      if ('code' in result && !('result' in result && result.result)) {
        const error = 'message' in result && result.message
          ? hexToString(result.message)
          : result.code.toString();

        logDebugError('submitTransfer', { error, result });

        return { error };
      }

      return { amount, toAddress, txId: result.transaction.txID };
    }
  } catch (err: any) {
    logDebugError('submitTransfer', err);
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

async function estimateTrc20TransferFee(tronWeb: TronWeb, options: {
  network: ApiNetwork;
  tokenAddress: string;
  toAddress: string;
  amount?: bigint;
  energyUnitFee: number;
  fromAddress: string;
}) {
  const {
    network, tokenAddress, toAddress, energyUnitFee, fromAddress,
  } = options;

  let { amount } = options;
  const tokenBalance = await getTrc20Balance(network, tokenAddress, fromAddress);

  if (!tokenBalance) {
    return TRON_GAS.transferTrc20Estimated;
  }

  if (amount === undefined || amount > tokenBalance) {
    amount = 1n;
  }

  // This call throws "Error: REVERT opcode executed" when the given amount is more than the token balance.
  // It doesn't throw when the amount is 0.
  const { energy_required: energyRequired } = await tronWeb.transactionBuilder.estimateEnergy(
    tokenAddress,
    'transfer(address,uint256)',
    {},
    [
      { type: 'address', value: toAddress },
      { type: 'uint256', value: Number(amount) },
    ],
    fromAddress,
  );

  return BigInt(energyUnitFee * energyRequired);
}

async function buildTrc20Transfer(tronWeb: TronWeb, options: {
  tokenAddress: string;
  toAddress: string;
  amount: bigint;
  feeLimit: bigint;
  fromAddress: string;
}) {
  const {
    amount, tokenAddress, toAddress, feeLimit, fromAddress,
  } = options;

  const { transaction } = await tronWeb.transactionBuilder.triggerSmartContract(
    tokenAddress,
    'transfer(address,uint256)',
    { feeLimit: Number(feeLimit) },
    [
      { type: 'address', value: toAddress },
      { type: 'uint256', value: Number(amount) },
    ],
    fromAddress,
  );

  return { transaction };
}
