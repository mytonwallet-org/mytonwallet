// Importing from `tronweb/lib/commonjs/types` breaks eslint (eslint doesn't like any of import placement options)
// eslint-disable-next-line simple-import-sort/imports
import type { TronWeb } from 'tronweb';
import type { ContractParamter, Transaction } from 'tronweb/lib/commonjs/types';

import type { ApiSubmitTransferOptions, CheckTransactionDraftOptions } from '../../methods/types';
import type { ApiCheckTransactionDraftResult } from '../ton/types';
import { ApiTransactionDraftError, ApiTransactionError } from '../../types';
import type { ApiAccountWithMnemonic, ApiBip39Account } from '../../types';

import { parseAccountId } from '../../../util/account';
import { logDebugError } from '../../../util/logs';
import { getChainParameters, getTronClient } from './util/tronweb';
import { fetchStoredAccount, fetchStoredTronWallet } from '../../common/accounts';
import { getMnemonic } from '../../common/mnemonic';
import { handleServerError } from '../../errors';
import { getWalletBalance } from './wallet';
import type { ApiSubmitTransferTronResult } from './types';
import { hexToString } from '../../../util/stringFormat';
import { ONE_TRX } from './constants';
import { getChainConfig } from '../../../util/chain';

const SIGNATURE_SIZE = 65;

const chainConfig = getChainConfig('tron');

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

    const { address } = await fetchStoredTronWallet(accountId);
    const [trxBalance, bandwidth, { energyUnitFee, bandwidthUnitFee }] = await Promise.all([
      getWalletBalance(network, address),
      tronWeb.trx.getBandwidth(address),
      getChainParameters(network),
    ]);

    let transaction: Transaction<ContractParamter>;
    let fee = 0n;

    if (tokenAddress) {
      const buildResult = await buildTrc20Transaction(tronWeb, {
        toAddress,
        tokenAddress,
        amount,
        energyUnitFee,
        feeLimitTrx: chainConfig.gas.maxTransferToken,
        fromAddress: address,
      });

      transaction = buildResult.transaction;
      fee = BigInt(buildResult.energyFee);
    } else {
      transaction = await tronWeb.transactionBuilder.sendTrx(toAddress, Number(amount), address);
    }

    const size = 9 + 60 + Buffer.from(transaction.raw_data_hex, 'hex').byteLength + SIGNATURE_SIZE;
    fee += bandwidth > size ? 0n : BigInt(size) * BigInt(bandwidthUnitFee);

    const trxAmount = tokenAddress ? fee : amount + fee;
    if (trxBalance < trxAmount) {
      return {
        resolvedAddress: toAddress,
        fee,
        error: ApiTransactionDraftError.InsufficientBalance,
      };
    }

    return {
      resolvedAddress: toAddress,
      fee,
    };
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
    accountId, password, toAddress, amount, fee = 0n, tokenAddress,
  } = options;

  const { network } = parseAccountId(accountId);

  try {
    const tronWeb = getTronClient(network);

    const account = await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
    const { address } = (account as ApiBip39Account).tron;
    const trxBalance = await getWalletBalance(network, address);

    const trxAmount = tokenAddress ? fee : fee + amount;
    const isEnoughTrx = (trxBalance - ONE_TRX) >= trxAmount;

    if (!isEnoughTrx) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const mnemonic = await getMnemonic(accountId, password, account);
    const privateKey = tronWeb.fromMnemonic(mnemonic!.join(' ')).privateKey.slice(2);

    if (tokenAddress) {
      const feeLimitTrx = chainConfig.gas.maxTransferToken;
      const { energyUnitFee } = await getChainParameters(network);

      const { transaction, energyFee } = await buildTrc20Transaction(tronWeb, {
        toAddress, tokenAddress, amount, feeLimitTrx, energyUnitFee, fromAddress: address,
      });

      if (energyFee > Number(feeLimitTrx)) {
        return { error: ApiTransactionDraftError.InsufficientBalance };
      }

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

async function buildTrc20Transaction(tronWeb: TronWeb, options: {
  tokenAddress: string;
  toAddress: string;
  amount: bigint;
  feeLimitTrx: bigint;
  energyUnitFee: number;
  fromAddress: string;
}) {
  const {
    tokenAddress, toAddress, amount, feeLimitTrx, energyUnitFee, fromAddress,
  } = options;

  const functionSelector = 'transfer(address,uint256)';
  const parameter = [
    { type: 'address', value: toAddress },
    { type: 'uint256', value: Number(amount) },
  ];

  const { transaction } = await tronWeb.transactionBuilder.triggerSmartContract(
    tokenAddress,
    functionSelector,
    { feeLimit: Number(feeLimitTrx) },
    parameter,
    fromAddress,
  );

  const { energy_used: energyUsed } = await tronWeb.transactionBuilder.triggerConstantContract(
    tokenAddress,
    functionSelector,
    {},
    parameter,
    fromAddress,
  );

  const energyFee = energyUnitFee * energyUsed!;

  return { transaction, energyFee };
}
