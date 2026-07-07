import { Cell } from '@ton/core';

import type {
  ApiAccountWithChain,
  ApiAnyDisplayError,
  ApiNetwork,
  ApiSwapActivity,
  ApiSwapBuildTransactionRequest,
  ApiSwapTransfer,
  ApiTokensTransferPayload,
  OnApiUpdate,
} from '../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiBuildOnchainSwapTransferResult,
  ApiSubmitOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferResult,
} from '../../types/swap';
import type { TonTransferParams } from './types';

import { DIESEL_ADDRESS, SWAP_FEE_ADDRESS } from '../../../config';
import { parseAccountId } from '../../../util/account';
import { assert as originalAssert } from '../../../util/assert';
import { fromDecimal } from '../../../util/decimals';
import { omitUndefined } from '../../../util/iteratees';
import { getMaxMessagesInTransaction, isTokenTransferPayload } from '../../../util/ton/transfer';
import { parsePayloadSlice } from './util/metadata';
import { resolveTokenWalletAddress, toBase64Address } from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import { getTokenByAddress } from '../../common/tokens';
import { callHook } from '../../hooks';
import { insertMintlessPayload } from './tokens';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from './transfer';
import { getContractInfo } from './wallet';

async function getContractInfos(network: ApiNetwork, addresses: string[]) {
  // Can't be done via Toncenter `/api/v3/accountStates` endpoint because it serializes code cells
  // differently, resulting in `codeHashOld` mismatch
  const result: Record<string, Awaited<ReturnType<typeof getContractInfo>>> = {};
  const infos = await Promise.all(addresses.map((address) => getContractInfo(network, address)));
  for (let i = 0; i < addresses.length; i++) {
    result[addresses[i]] = infos[i];
  }
  return result;
}

const FEE_ADDRESSES = [SWAP_FEE_ADDRESS, DIESEL_ADDRESS];
const MAX_NETWORK_FEE = 3600000000n; // 3.6 TON = 0.3 TON * 3 * 4 - when 4 splits with 3 hops per split on Stonfi
const MAX_SPLITS = 4; // Backend configuration

export async function validateDexSwapTransfers(
  network: ApiNetwork,
  address: string,
  request: ApiSwapBuildTransactionRequest,
  transfers: TonTransferParams[],
  account: ApiAccountWithChain<'ton'>,
) {
  const feeTransfer = (
    toBase64Address(transfers.at(-1)?.toAddress ?? '', false) === SWAP_FEE_ADDRESS
  ) ? transfers.at(-1)! : undefined;
  const mainTransfers = feeTransfer ? transfers.slice(0, -1) : transfers;
  const maxMessages = getMaxMessagesInTransaction(account);
  const maxSplits = Math.min(maxMessages - (feeTransfer ? 1 : 0), MAX_SPLITS);

  const assert = (condition: boolean, message: string) => {
    originalAssert(condition, message, {
      network, address, request, transfers, maxMessages, maxSplits,
    });
  };

  assert(mainTransfers.length <= maxSplits, 'Too many main transfers');

  // FIXME: TON renaming
  if (request.from === 'TON') {
    const maxAmount = fromDecimal(request.fromAmount) + fromDecimal(request.ourFee ?? 0) + MAX_NETWORK_FEE;
    let sumAmount = 0n;

    const contractInfos = await getContractInfos(network, mainTransfers.map((transfer) => transfer.toAddress));

    for (let i = 0; i < mainTransfers.length; i++) {
      const mainTransfer = mainTransfers[i];
      sumAmount += mainTransfer.amount;
      const { isSwapAllowed, codeHash } = contractInfos[mainTransfer.toAddress];
      assert(
        !!isSwapAllowed,
        `Main transfer ${i + 1}/${mainTransfers.length} is not to a swap contract: `
        + `toAddress=${mainTransfer.toAddress}, codeHash=${codeHash}`,
      );
    }

    assert(sumAmount <= maxAmount, 'Main transfers amount is too big');

    if (feeTransfer) {
      assert(feeTransfer.amount <= sumAmount, 'Fee transfer amount is bigger than main transfers amount');
      assert(feeTransfer.amount + sumAmount < maxAmount, 'Total amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeTransfer.toAddress, false)), 'Unexpected fee transfer address');
    }
  } else {
    const token = getTokenByAddress(request.from)!;
    assert(!!token, 'Unknown "from" token');

    const maxAmount = fromDecimal(request.fromAmount, token.decimals)
      + fromDecimal(request.ourFee ?? 0, token.decimals)
      + fromDecimal(request.dieselFee ?? 0, token.decimals);
    const maxTonAmount = MAX_NETWORK_FEE;

    const walletAddress = await resolveTokenWalletAddress(network, address, token.tokenAddress!);
    let sumTokenAmount = 0n;
    let sumTonAmount = 0n;

    const parsedPayloads = await Promise.all(mainTransfers.map(
      async (transfer) => transfer.payload
        && parsePayloadSlice(network, transfer.toAddress, transfer.payload.beginParse()),
    ));
    const contractInfos = await getContractInfos(
      network,
      parsedPayloads.filter(isTokenTransferPayload).map((payload) => payload.destination),
    );
    for (let i = 0; i < mainTransfers.length; i++) {
      const mainTransfer = mainTransfers[i];
      const parsedPayload = parsedPayloads[i];

      assert(
        mainTransfer.toAddress === walletAddress,
        `Main transfer ${i + 1}/${mainTransfers.length} address is not the token wallet address`,
      );
      assert(
        isTokenTransferPayload(parsedPayload),
        `Main transfer ${i + 1}/${mainTransfers.length} payload is not a token transfer`,
      );

      const { amount: tokenAmount, destination } = parsedPayload as ApiTokensTransferPayload;
      sumTokenAmount += tokenAmount;
      sumTonAmount += mainTransfer.amount;

      const { isSwapAllowed, codeHash } = contractInfos[destination];

      assert(
        isSwapAllowed || FEE_ADDRESSES.includes(toBase64Address(destination, false)),
        `Main transfer ${i + 1}/${mainTransfers.length} destination is not a swap smart contract: `
        + `${destination}, codeHash=${codeHash}`,
      );
    }
    assert(sumTokenAmount <= maxAmount, 'Main transfers token amount is too big');
    assert(sumTonAmount <= maxTonAmount, 'Main transfers TON amount is too big');

    if (feeTransfer) {
      const feePayload = feeTransfer.payload
        && await parsePayloadSlice(network, feeTransfer.toAddress, feeTransfer.payload.beginParse());

      assert(feeTransfer.amount + sumTonAmount < maxTonAmount, 'Total TON amount is too big');
      assert(feeTransfer.toAddress === walletAddress, 'Fee transfer address is not the token wallet address');
      assert(isTokenTransferPayload(feePayload), 'Fee transfer payload is not a token transfer');

      const { amount: tokenFeeAmount, destination: feeDestination } = feePayload as ApiTokensTransferPayload;

      assert(sumTokenAmount + tokenFeeAmount <= maxAmount, 'Total token amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeDestination, false)), 'Unexpected fee transfer destination');
    }
  }
}

export async function buildOnchainSwapTransfer(
  options: ApiBuildOnchainSwapTransferOptions,
): Promise<ApiBuildOnchainSwapTransferResult | { error: ApiAnyDisplayError }> {
  const { accountId, request, transfers, swapId, authToken } = options;

  if (!transfers) {
    throw new Error('Transfers are required');
  }

  const transferList = parseSwapTransfers(transfers);
  const { network } = parseAccountId(accountId);

  const { address } = await fetchStoredWallet(accountId, 'ton');

  try {
    const account = await fetchStoredChainAccount(accountId, 'ton');
    await validateDexSwapTransfers(network, address, request, transferList, account);

    const result = await checkMultiTransactionDraft(accountId, transferList, request.shouldTryDiesel);

    if ('error' in result) {
      await patchSwapItem({
        address, swapId, authToken, error: result.error,
      });
      return result;
    }

    return { ...result, id: swapId, transfers, chain: 'ton' };
  } catch (err: any) {
    await patchSwapItem({
      address, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

export async function submitOnchainSwapTransfer(
  options: ApiSubmitOnchainSwapTransferOptions,
  onUpdate: OnApiUpdate,
): Promise<ApiSubmitOnchainSwapTransferResult> {
  const {
    accountId,
    password,
    transfers,
    historyItem,
    isGasless,
    authToken,
    localSwap,
    swapId,
  } = options;

  if (!transfers) {
    throw new Error('Transfers are required');
  }

  const wallet = await fetchStoredWallet(accountId, 'ton');
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const hasMfa = Boolean(account.byChain.ton.mfa);

  const { address } = wallet;

  // For MFA wallets, the local activity is created only after the request is confirmed
  if (!hasMfa) {
    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [localSwap],
    });
  }

  try {
    const transferList = parseSwapTransfers(transfers);

    if (historyItem.from !== 'TON') {
      transferList[0] = await insertMintlessPayload('mainnet', address, historyItem.from, transferList[0]);
    }

    const result = await submitMultiTransferWithMfa({
      accountId,
      password,
      messages: transferList,
      isGasless,
    });

    if ('error' in result) {
      if (!hasMfa) {
        // Update local activity to show error state
        onUpdate({
          type: 'newLocalActivities',
          accountId,
          activities: [{ ...localSwap, status: 'failed' }],
        });
      }

      await patchSwapItem({
        address, swapId, authToken, error: result.error,
      });

      return result;
    }

    if ('mfaRequest' in result) {
      return { mfaRequest: result.mfaRequest };
    }

    delete result.messages[0].stateInit;

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: result.msgHashNormalized,
      extra: omitUndefined({
        withW5Gasless: result.withW5Gasless,
      }),
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address, swapId, authToken, msgHash: result.msgHash,
    });

    void callHook('onSwapCreated', accountId, updatedSwap.timestamp - 1);

    return { activityId: updatedSwap.id };
  } catch (err: any) {
    if (!hasMfa) {
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [{ ...localSwap, status: 'failed' }],
      });
    }

    await patchSwapItem({
      address, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

function parseSwapTransfers(transfers: ApiSwapTransfer[]): TonTransferParams[] {
  return transfers.map((transfer) => ({
    ...transfer,
    amount: BigInt(transfer.amount),
    payload: Cell.fromBase64(transfer.payload),
  }));
}

function errorToString(err: Error | string) {
  return typeof err === 'string' ? err : err.stack;
}
