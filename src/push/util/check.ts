import type { ApiCheck } from '../types';
import type { ContractVersion } from './contractController';

import { NETWORK, PUSH_API_URL, PUSH_SC_VERSIONS } from '../config';
import { fetchJson } from '../../util/fetch';
import { getTelegramApp } from '../../util/telegram';
import { getWalletBalance } from '../../api/chains/ton';
import { getTokenBalance, resolveTokenWalletAddress } from '../../api/chains/ton/util/tonCore';
import * as checkJwt from './checkJwt';
import * as checkStandard from './checkStandard';
import { cashCheck } from './contractController';
import { tonConnectUi } from './tonConnect';

import { PushEscrowJwt } from '../../api/chains/ton/contracts/PushEscrowJwt';
import { PushEscrow as PushEscrowV3 } from '../../api/chains/ton/contracts/PushEscrowV3';

function isJwtContract(contractAddress: string): boolean {
  return PUSH_SC_VERSIONS.jwtV1 === contractAddress;
}

export async function fetchAccountBalance(ownerAddress: string, tokenAddress?: string) {
  if (!tokenAddress) {
    return getWalletBalance(NETWORK, ownerAddress);
  }

  const jettonWalletAddress = await resolveTokenWalletAddress(NETWORK, ownerAddress, tokenAddress);

  return getTokenBalance(NETWORK, jettonWalletAddress);
}

export async function fetchCheck(checkKey: string) {
  const response = await fetch(`${PUSH_API_URL}/checks/${checkKey}?${getTelegramApp()!.initData}`);
  const result = await response.json();

  return result?.check as ApiCheck;
}

export async function processCreateCheck(check: ApiCheck, onSend: NoneToVoidFunction) {
  const userAddress = tonConnectUi.wallet!.account.address;
  const message = isJwtContract(check.contractAddress)
    ? await checkJwt.processCreateCheck(check as any, userAddress)
    : await checkStandard.processCreateCheck(check as any, userAddress);

  await tonConnectUi.sendTransaction({
    validUntil: Math.floor(Date.now() / 1000) + 360,
    messages: [message],
  });

  onSend();

  await fetch(`${PUSH_API_URL}/checks/${check.id}/mark_sending`, { method: 'POST' });
}

export async function processToggleInvoice(check: ApiCheck, onSend: NoneToVoidFunction) {
  try {
    const url = `${PUSH_API_URL}/checks/${check.id}/toggle_invoice?${getTelegramApp()!.initData}`;
    const { ok, isInvoice } = await (fetchJson(url, undefined, { method: 'POST' }));
    if (!ok) return undefined;

    return isInvoice;
  } catch (err: any) {
    return undefined;
  }
}

export async function processCashCheck(
  check: ApiCheck, onSend: NoneToVoidFunction, userAddress: string, isReturning = false, jwt?: string,
) {
  const { id: checkId, contractAddress } = check;

  const scVersion: ContractVersion = {
    isV1: PUSH_SC_VERSIONS.v1.includes(contractAddress),
    isV2: PUSH_SC_VERSIONS.v2 === contractAddress,
    isV3: PUSH_SC_VERSIONS.v3.includes(contractAddress),
    isNft: PUSH_SC_VERSIONS.NFT === contractAddress,
    isJwt: PUSH_SC_VERSIONS.jwtV1 === contractAddress,
  };

  const checkData = scVersion.isJwt
    ? await checkJwt.processCashCheck(check as any, userAddress, jwt!)
    : await checkStandard.processCashCheck(check as any, userAddress, isReturning, scVersion);

  await cashCheck(contractAddress, scVersion, checkId, checkData);

  onSend();

  await fetch(
    `${PUSH_API_URL}/checks/${checkId}/mark_receiving${isReturning ? '?is_returning=true' : ''}`,
    { method: 'POST' },
  );
}

export async function processCancelCheck(check: ApiCheck, onSend: NoneToVoidFunction) {
  const cancelFee = isJwtContract(check.contractAddress)
    ? checkJwt.processCancelCheck()
    : checkStandard.processCancelCheck();

  const payload = isJwtContract(check.contractAddress)
    ? PushEscrowJwt.prepareCancelCheck({ checkId: check.id })
    : PushEscrowV3.prepareCancelCheck({ checkId: check.id });

  await tonConnectUi.sendTransaction({
    validUntil: Math.floor(Date.now() / 1000) + 360,
    messages: [{
      address: check.contractAddress,
      amount: String(cancelFee),
      payload: payload.toBoc().toString('base64'),
    }],
  });

  onSend();

  await fetch(
    `${PUSH_API_URL}/checks/${check.id}/mark_receiving?is_returning=true`,
    { method: 'POST' },
  );
}
