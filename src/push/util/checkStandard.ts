import { Address } from '@ton/core';

import type { ApiStandardCheck } from '../types';
import type { ContractVersion } from './contractController';

import { NETWORK } from '../config';
import { signCustomData } from '../../util/authApi/telegram';
import { fromDecimal } from '../../util/decimals';
import { getTranslation } from '../../util/langProvider';
import { getTelegramApp } from '../../util/telegram';
import { buildNftTransferPayload } from '../../api/chains/ton/nfts';
import { buildTokenTransferBody, getTonClient, resolveTokenWalletAddress } from '../../api/chains/ton/util/tonCore';
import { calcAddressHashBase64, calcAddressHead, calcAddressWithCheckIdSha256HeadBase64 } from './addressEncoders';

import { CANCEL_FEE, Fees, PushEscrow as PushEscrowV3 } from '../../api/chains/ton/contracts/PushEscrowV3';
import { Fees as NftFees, PushNftEscrow } from '../../api/chains/ton/contracts/PushNftEscrow';

const TINY_JETTONS = ['EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs']; // USDT
const TON_FULL_FEE = Fees.TON_CREATE_GAS + Fees.TON_CASH_GAS + Fees.TON_TRANSFER;
const JETTON_FULL_FEE = Fees.JETTON_CREATE_GAS + Fees.JETTON_CASH_GAS + Fees.JETTON_TRANSFER + Fees.TON_TRANSFER;
// eslint-disable-next-line @stylistic/max-len
const TINY_JETTON_FULL_FEE = Fees.JETTON_CREATE_GAS + Fees.JETTON_CASH_GAS + Fees.TINY_JETTON_TRANSFER + Fees.TON_TRANSFER;
const NFT_FULL_FEE = NftFees.NFT_CREATE_GAS + NftFees.NFT_CASH_GAS + NftFees.NFT_TRANSFER + Fees.TON_TRANSFER;
const ANONYMOUS_NUMBER_COLLECTION = '0:0e41dc1dc3c9067ed24248580e12b3359818d83dee0304fabcf80845eafafdb2';

export async function processCreateCheck(check: ApiStandardCheck, userAddress: string) {
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
    const jettonWalletAddress = await resolveTokenWalletAddress(NETWORK, userAddress, check.minterAddress!);
    if (!jettonWalletAddress) {
      throw new Error('Could not resolve jetton wallet address');
    }

    const isTinyJetton = TINY_JETTONS.includes(check.minterAddress!);
    const messageAmount = String(
      isTinyJetton
        ? Fees.TINY_JETTON_TRANSFER + TINY_JETTON_FULL_FEE
        : Fees.JETTON_TRANSFER + JETTON_FULL_FEE,
    );
    const forwardAmount = isTinyJetton ? TINY_JETTON_FULL_FEE : JETTON_FULL_FEE;

    message = {
      address: jettonWalletAddress,
      amount: messageAmount,
      payload: buildTokenTransferBody({
        tokenAmount: amount,
        toAddress: contractAddress,
        responseAddress: userAddress,
        forwardAmount,
        forwardPayload: payload,
        noInlineForwardPayload: true, // Not sure whether it's necessary; setting true to be on the safe side
      }).toBoc().toString('base64'),
    };
  } else if (isNftTransfer) {
    const { nftInfo } = check;

    if (
      (nftInfo.isTelegramGift || nftInfo.collectionAddress === ANONYMOUS_NUMBER_COLLECTION)
      && await isOnSaleOnFragment(nftInfo.address)) {
      throw new Error(getTranslation('Before transferring this NFT, please remove it from sale on Fragment.'));
    }

    const messageAmount = String(NFT_FULL_FEE + NftFees.NFT_TRANSFER);

    message = {
      address: nftInfo.address,
      amount: messageAmount,
      payload: buildNftTransferPayload({
        fromAddress: userAddress,
        toAddress: contractAddress,
        payload,
        forwardAmount: NFT_FULL_FEE,
        noInlinePayload: true,
      }).toBoc().toString('base64'),
    };
  } else {
    const messageAmount = String(amount + TON_FULL_FEE);

    message = {
      address: contractAddress,
      amount: messageAmount,
      payload: payload.toBoc().toString('base64'),
    };
  }

  return message;
}

async function isOnSaleOnFragment(giftAddress: string) {
  const { stack } = await getTonClient(NETWORK).runMethod(
    Address.parse(giftAddress), 'get_telemint_auction_config',
  );

  return Boolean(stack.readAddressOpt());
}

export async function processCashCheck(
  check: ApiStandardCheck,
  userAddress: string,
  isReturning: boolean,
  scVersion: ContractVersion,
) {
  const { id: checkId, chatInstance, username } = check;

  let payload: string;
  if (scVersion.isV1) {
    payload = calcAddressHead(userAddress);
  } else if (scVersion.isV2) {
    payload = await calcAddressWithCheckIdSha256HeadBase64(checkId, userAddress);
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

  return {
    authDate: resultUnsafe.auth_date,
    ...(username ? {
      username: resultUnsafe.init_data.user!.username,
    } : {
      chatInstance: resultUnsafe.init_data.chat_instance,
    }),
    receiverAddress: userAddress,
    signature: resultUnsafe.signature,
  };
}

export function processCancelCheck() {
  return CANCEL_FEE;
}
