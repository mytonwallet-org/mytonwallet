import type { ApiCheck } from '../types';

import { DEBUG } from '../../config';
import { PUSH_API_URL, PUSH_SC_VERSIONS } from '../config';
import { signCustomData } from '../../util/authApi/telegram';
import { fromDecimal } from '../../util/decimals';
import { fetchJson } from '../../util/fetch';
import { getTelegramApp } from '../../util/telegram';
import { getWalletBalance, resolveTokenWalletAddress } from '../../api/chains/ton';
import { buildNftTransferPayload } from '../../api/chains/ton/nfts';
import { buildTokenTransferBody, getTokenBalance } from '../../api/chains/ton/util/tonCore';
import { calcAddressHashBase64, calcAddressHead, calcAddressSha256HeadBase64, cashCheck } from './push';
import { tonConnectUi } from './tonConnect';

import { CANCEL_FEE, Fees, PushEscrow as PushEscrowV3 } from '../../api/chains/ton/contracts/PushEscrowV3';
import { Fees as NftFees, PushNftEscrow } from '../../api/chains/ton/contracts/PushNftEscrow';

const TINY_JETTONS = ['EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs']; // USDT
const TON_FULL_FEE = Fees.TON_CREATE_GAS + Fees.TON_CASH_GAS + Fees.TON_TRANSFER;
const JETTON_FULL_FEE = Fees.JETTON_CREATE_GAS + Fees.JETTON_CASH_GAS + Fees.JETTON_TRANSFER + Fees.TON_TRANSFER;
// eslint-disable-next-line @stylistic/max-len
const TINY_JETTON_FULL_FEE = Fees.JETTON_CREATE_GAS + Fees.JETTON_CASH_GAS + Fees.TINY_JETTON_TRANSFER + Fees.TON_TRANSFER;
const NFT_FULL_FEE = NftFees.NFT_CREATE_GAS + NftFees.NFT_CASH_GAS + NftFees.NFT_TRANSFER + Fees.TON_TRANSFER;

export async function fetchAccountBalance(ownerAddress: string, tokenAddress?: string) {
  if (!tokenAddress) {
    return getWalletBalance('mainnet', ownerAddress);
  }

  const jettonWalletAddress = await resolveTokenWalletAddress('mainnet', ownerAddress, tokenAddress);

  return getTokenBalance('mainnet', jettonWalletAddress);
}

export async function fetchCheck(checkKey: string) {
  const response = await fetch(`${PUSH_API_URL}/checks/${checkKey}?${getTelegramApp()!.initData}`);
  const result = await response.json();

  return result?.check as ApiCheck;
}

export async function processCreateCheck(check: ApiCheck, onSend: NoneToVoidFunction) {
  try {
    const userAddress = tonConnectUi.wallet!.account.address;
    const { id: checkId, type, contractAddress, username, comment } = check;

    const isJettonTransfer = type === 'coin' && Boolean(check.minterAddress);
    const isNftTransfer = type === 'nft';

    const amount = check.type === 'coin' ? fromDecimal(check.amount, check.decimals) : 0n;
    const chatInstance = !username ? getTelegramApp()!.initDataUnsafe.chat_instance! : undefined;
    const params = { checkId, amount, username, chatInstance, comment };
    const payload = isJettonTransfer
      ? PushEscrowV3.prepareCreateJettonCheckForwardPayload(params)
      : isNftTransfer
        ? PushNftEscrow.prepareCreateCheck(params)
        : PushEscrowV3.prepareCreateCheck(params);

    let message;

    if (isJettonTransfer) {
      const jettonWalletAddress = await resolveTokenWalletAddress('mainnet', userAddress, check.minterAddress!);
      if (!jettonWalletAddress) {
        throw new Error('Could not resolve jetton wallet address');
      }

      const isTinyJetton = TINY_JETTONS.includes(check.minterAddress!);
      const messageAmount = String(
        isTinyJetton
          ? Fees.TINY_JETTON_TRANSFER + TINY_JETTON_FULL_FEE
          : Fees.JETTON_TRANSFER + JETTON_FULL_FEE,
      );

      message = {
        address: jettonWalletAddress,
        amount: messageAmount,
        payload: buildTokenTransferBody({
          tokenAmount: amount,
          toAddress: contractAddress,
          responseAddress: userAddress,
          forwardAmount: isTinyJetton ? TINY_JETTON_FULL_FEE : JETTON_FULL_FEE,
          forwardPayload: payload,
        }).toBoc().toString('base64'),
      };
    } else if (isNftTransfer) {
      const { nftInfo } = check;
      const messageAmount = String(NFT_FULL_FEE + NftFees.NFT_TRANSFER);

      message = {
        address: nftInfo.address,
        amount: messageAmount,
        payload: buildNftTransferPayload(
          userAddress,
          contractAddress,
          payload,
          NFT_FULL_FEE,
        ).toBoc().toString('base64'),
      };
    } else {
      const messageAmount = String(amount + TON_FULL_FEE);

      message = {
        address: contractAddress,
        amount: messageAmount,
        payload: payload.toBoc().toString('base64'),
      };
    }

    await tonConnectUi.sendTransaction({
      validUntil: Math.floor(Date.now() / 1000) + 360,
      messages: [message],
    });

    onSend();

    await fetch(`${PUSH_API_URL}/checks/${check.id}/mark_sending`, { method: 'POST' });
  } catch (err) {
    if (DEBUG) {
      // eslint-disable-next-line no-console
      console.error('Failed to sign transaction', err);
    }
  }
}

export async function processToggleInvoice(check: ApiCheck, onSend: NoneToVoidFunction) {
  try {
    const url = `${PUSH_API_URL}/checks/${check.id}/toggle_invoice?${getTelegramApp()!.initData}`;
    const { ok, isInvoice } = await (fetchJson(url, undefined, { method: 'POST' }) as Promise<{
      ok?: boolean;
      isInvoice?: boolean;
    }>);
    if (!ok) return undefined;

    return isInvoice;
  } catch (err: any) {
    return undefined;
  }
}

export async function processCashCheck(
  check: ApiCheck, onSend: NoneToVoidFunction, userAddress: string, isReturning = false,
) {
  const { id: checkId, contractAddress, chatInstance, username } = check;

  const scVersion = {
    isV1: PUSH_SC_VERSIONS.v1.includes(contractAddress),
    isV2: PUSH_SC_VERSIONS.v2 === contractAddress,
    isV3: PUSH_SC_VERSIONS.v3.includes(contractAddress),
    isNft: PUSH_SC_VERSIONS.NFT === contractAddress,
  };

  let payload: string;
  if (scVersion.isV1) {
    payload = calcAddressHead(userAddress);
  } else if (scVersion.isV2) {
    payload = await calcAddressSha256HeadBase64(checkId, userAddress);
  } else { // isV3
    payload = calcAddressHashBase64(userAddress);
  }

  const { resultUnsafe } = (await signCustomData(
    username ? { user: { username: true } } : { chat_instance: true },
    payload,
    (scVersion.isV3 || scVersion.isNft) ? {
      shouldSignHash: true,
      isPayloadBinary: true,
    } : undefined,
  ));

  if (!isReturning && (
    (username && resultUnsafe.init_data.user?.username !== username)
    || (!username && resultUnsafe.init_data.chat_instance !== chatInstance)
  )) {
    throw new Error('Access to transfer denied');
  }

  await cashCheck(contractAddress, scVersion, checkId, {
    authDate: resultUnsafe.auth_date,
    ...(username ? {
      username: resultUnsafe.init_data.user!.username,
    } : {
      chatInstance: resultUnsafe.init_data.chat_instance,
    }),
    receiverAddress: userAddress,
    signature: resultUnsafe.signature,
  });

  onSend();

  await fetch(
    `${PUSH_API_URL}/checks/${checkId}/mark_receiving${isReturning ? '?is_returning=true' : ''}`,
    { method: 'POST' },
  );
}

export async function processCancelCheck(check: ApiCheck, onSend: NoneToVoidFunction) {
  const payload = PushEscrowV3.prepareCancelCheck({ checkId: check.id });

  await tonConnectUi.sendTransaction({
    validUntil: Math.floor(Date.now() / 1000) + 360,
    messages: [{
      address: check.contractAddress,
      amount: String(CANCEL_FEE),
      payload: payload.toBoc().toString('base64'),
    }],
  });

  onSend();

  await fetch(
    `${PUSH_API_URL}/checks/${check.id}/mark_receiving?is_returning=true`,
    { method: 'POST' },
  );
}
