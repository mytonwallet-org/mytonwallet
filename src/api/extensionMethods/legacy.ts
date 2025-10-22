import { Cell } from '@ton/core';

import type { AnyTonTransferPayload } from '../chains/ton/types';
import type { OnApiUpdate } from '../types';
import type { OnApiSiteUpdate } from '../types/dappUpdates';

import { TONCOIN } from '../../config';
import { parseAccountId } from '../../util/account';
import * as ton from '../chains/ton';
import {
  fetchStoredAccount,
  fetchStoredWallet,
  getCurrentAccountId,
  getCurrentAccountIdOrFail,
  waitLogin,
} from '../common/accounts';
import { createDappPromise } from '../common/dappPromises';
import { base64ToBytes, hexToBytes } from '../common/utils';
import { createLocalTransactions } from '../methods';
import { openPopupWindow } from './window';

let onPopupUpdate: OnApiUpdate;

export function initLegacyDappMethods(_onPopupUpdate: OnApiUpdate) {
  onPopupUpdate = _onPopupUpdate;
}

export async function onDappSendUpdates(onDappUpdate: OnApiSiteUpdate) {
  const accounts = await requestAccounts();

  onDappUpdate({
    type: 'updateAccounts',
    accounts,
  });
}

export async function getBalance() {
  const accountId = await getCurrentAccountIdOrFail();
  const { network } = parseAccountId(accountId);
  const account = await fetchStoredAccount(accountId);
  const wallet = account.byChain.ton;

  return wallet ? ton.getWalletBalance(network, wallet.address) : 0n;
}

export async function requestAccounts() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    return [];
  }

  const { byChain: { ton: tonWallet } } = await fetchStoredAccount(accountId);
  if (!tonWallet) {
    return [];
  }

  return [tonWallet.address];
}

export async function requestWallets() {
  const accountId = await getCurrentAccountId();
  if (!accountId) {
    return [];
  }

  const { byChain: { ton: tonWallet } } = await fetchStoredAccount(accountId);
  if (!tonWallet) {
    return [];
  }

  const { address, publicKey, version } = tonWallet;

  return [{
    address,
    publicKey,
    walletVersion: version,
  }];
}

export async function sendTransaction(params: {
  to: string;
  value: string;
  data?: string;
  dataType?: 'text' | 'hex' | 'base64' | 'boc';
  stateInit?: string;
}) {
  const accountId = await getCurrentAccountIdOrFail();

  const {
    value, to: toAddress, data, dataType, stateInit,
  } = params;
  const amount = BigInt(value);

  let payload: AnyTonTransferPayload | undefined;
  if (data) {
    switch (dataType) {
      case 'hex':
        payload = { type: 'binary', data: hexToBytes(data) };
        break;
      case 'base64':
        payload = { type: 'binary', data: base64ToBytes(data) };
        break;
      case 'boc':
        payload = Cell.fromBase64(data);
        break;
      default:
        payload = { type: 'comment', text: data };
    }
  }

  await openPopupWindow();
  await waitLogin();

  const transferOptions = {
    accountId,
    toAddress,
    amount,
    payload,
    stateInit,
  };

  const checkResult = await ton.checkTransactionDraft(transferOptions);

  if ('error' in checkResult) {
    onPopupUpdate({
      type: 'showError',
      error: checkResult.error,
    });

    return false;
  }

  const { promiseId, promise } = createDappPromise();

  onPopupUpdate({
    type: 'createTransaction',
    promiseId,
    toAddress,
    amount,
    ...(dataType === 'text' && {
      comment: data,
    }),
    checkResult,
  });

  const password: string | undefined = await promise;

  const result = await ton.submitGasfullTransfer({
    ...transferOptions,
    password,
  });

  if ('error' in result) {
    return false;
  }

  const { address: fromAddress } = await fetchStoredWallet(accountId, 'ton');
  const [localActivity] = createLocalTransactions(accountId, 'ton', [{
    ...result.localActivityParams,
    id: result.txId,
    amount,
    fromAddress,
    toAddress,
    fee: checkResult.realFee ?? checkResult.fee!,
    slug: TONCOIN.slug,
    ...(dataType === 'text' && {
      comment: data,
    }),
  }]);

  onPopupUpdate({
    type: 'completeTransaction',
    activityId: localActivity.id,
  });

  return true;
}

export async function rawSign({ data }: { data: string }) {
  const accountId = await getCurrentAccountIdOrFail();

  await openPopupWindow();
  await waitLogin();

  const { promiseId, promise } = createDappPromise();

  onPopupUpdate({
    type: 'createSignature',
    promiseId,
    dataHex: data,
  });

  const password = await promise;

  return ton.rawSign(accountId, password, data);
}
