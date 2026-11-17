import type { OpenedContract } from '@ton/core';
import {
  Address, beginCell, Cell, Dictionary,
  external, loadMessageRelaxed, SendMode, storeMessage, storeMessageRelaxed,
} from '@ton/core';
import { loadOutListExtendedV5R1 } from '@ton/ton/dist/wallets/v5r1/WalletV5R1Actions';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { ApiActivity, ApiEmulationResult, ApiNetwork } from '../../api/types';
import type { ApiTransaction } from '../types';

import { TONCOIN } from '../../config';
import { signCustomData } from '../../util/telegram';
import { WORKCHAIN } from '../../api/chains/ton/constants';
import { getExternalMsgHashNormalized } from '../../api/chains/ton/util/sendExternal';
import { getTonClient, toBase64Address } from '../../api/chains/ton/util/tonCore';
import { callMfaApiWithThrow } from '../api/connector';

import { MfaExtension, OpCode, prepareMessage } from '../../api/chains/ton/contracts/MfaExtension';

const NETWORK = 'mainnet';
const MFA_REFILL_SEND_MODE: number = SendMode.PAY_GAS_SEPARATELY | SendMode.IGNORE_ERRORS;
let openContract: OpenedContract<MfaExtension> | undefined;
let openContractAddress: string | undefined;

export async function resolveExtensionAddress(walletAddress: string, telegramId?: string): Promise<Address> {
  const address = Address.parse(walletAddress);

  const { exit_code, stack } = await getTonClient(NETWORK).runMethodWithError(address, 'get_extensions');

  if (exit_code !== 0) throw new Error('Invalid wallet');

  const extensionsCell = stack.readCellOpt();
  if (!extensionsCell) throw new Error('Uninstalled');

  const extensionsDict = Dictionary.loadDirect(
    Dictionary.Keys.BigUint(256),
    Dictionary.Values.BigInt(1),
    extensionsCell,
  );

  const keys = extensionsDict.keys();
  const extensions = keys.map((key) =>
    Address.parseRaw(`${WORKCHAIN}:${key.toString(16).padStart(64, '0')}`),
  );

  for (const extension of extensions) {
    const contract = getTonClient(NETWORK).open(MfaExtension.createFromAddress(extension));

    try {
      const savedTelegramId = await contract.getTelegramId();

      if (!telegramId || savedTelegramId === telegramId) {
        return extension;
      }
    } catch {
      // Ignore non-MFA extensions and keep looking.
    }
  }

  throw new Error('Uninstalled');
}

function ensureOpenContract(extensionAddress: Address) {
  const address = extensionAddress.toRawString();

  if (!openContract || openContractAddress !== address) {
    openContract = getTonClient(NETWORK).open(MfaExtension.createFromAddress(extensionAddress));
    openContractAddress = address;
  }
}

export async function sendActions(
  payload: string,
  seedSignature: string,
  extensionAddress: Address,
) {
  ensureOpenContract(extensionAddress);

  const parsedPayload = Cell.fromBase64(payload);
  const parsedSignature = Buffer.from(seedSignature, 'base64');

  const { resultUnsafe } = await signCustomData(
    { user: { id: true } },
    parsedPayload.hash().toString('base64'),
    {
      shouldSignHash: true,
      isPayloadBinary: true,
    },
  );

  const parsedTelegramSignature = Buffer.from(resultUnsafe.signature, 'base64');

  const message = prepareMessage(
    parsedPayload,
    parsedSignature,
    parsedTelegramSignature,
    resultUnsafe.auth_date,
  );

  await openContract!.sendExternalMessage(message);

  // get external msg hash
  const ext = external({ to: extensionAddress, body: message });
  return getExternalMsgHashNormalized(ext);
}

export async function checkTransaction(
  telegramId: string,
  payload: string,
  extensionAddress: Address,
  address: string,
  mfaRefill: ApiTransaction['mfaRefill'],
): Promise<Pick<ApiEmulationResult, 'activities' | 'realFee'>> {
  ensureOpenContract(extensionAddress);

  const parsedPayload = Cell.fromBase64(payload).beginParse();

  const opCode = parsedPayload.loadUint(32) as OpCode;
  const seqno = parsedPayload.loadUint(32);
  const currentSeqno = await openContract!.getSeqno();

  if (seqno !== currentSeqno) {
    throw new Error('Expired');
  }

  if (opCode === OpCode.RECOVERY) {
    const validUntil = parsedPayload.loadUint(32);
    const now = Math.round(Date.now() / 1000);

    if (now > validUntil) {
      throw new Error('Expired');
    }
  }

  const telegramIdSaved = await openContract!.getTelegramId();
  if (telegramIdSaved !== telegramId) {
    throw new Error(`Account ${telegramId} is not authorized to sign message for wallet ${address}`);
  }

  if (opCode !== OpCode.SEND_ACTIONS) {
    return { activities: [], realFee: 0n };
  }

  return await emulatePayload(payload, address, extensionAddress, mfaRefill);
}

export async function emulatePayload(
  rawPayload: string,
  address: string,
  extensionAddress: Address,
  mfaRefill: ApiTransaction['mfaRefill'],
): Promise<Pick<ApiEmulationResult, 'activities' | 'realFee'>> {
  const message = Cell.fromBase64(rawPayload).beginParse();
  const outAction = message.loadRef().beginParse();
  const messageToWallet = outAction.loadRef();

  // patch message (add src)
  const messageRelaxed = loadMessageRelaxed(messageToWallet.beginParse());
  messageRelaxed.info.src = extensionAddress;
  const refillAmount = getTrustedMfaRefillAmount(rawPayload, messageRelaxed.body, extensionAddress, mfaRefill);

  const boc = beginCell().store(storeMessageRelaxed(messageRelaxed)).endCell()
    .toBoc()
    .toString('base64');
  const parsed = await callMfaApiWithThrow('emulateMfaMessage', NETWORK, address, boc);

  const { activities, wasHidden } = hideMfaRefillActivity(parsed.activities, extensionAddress, refillAmount);

  return {
    activities,
    // Charge the existing phi/fee only when the trusted marker exactly matched and hid the corresponding action.
    realFee: parsed.realFee + (wasHidden ? refillAmount! : 0n),
  };
}

export function getTrustedMfaRefillAmount(
  rawPayload: string,
  walletBody: Cell,
  extensionAddress: Address,
  marker: ApiTransaction['mfaRefill'],
): bigint | undefined {
  try {
    if (!marker || Cell.fromBase64(rawPayload).hash().toString('base64') !== marker.payloadHash) return undefined;
    const refillAmount = BigInt(marker.amount);
    if (refillAmount <= 0n) return undefined;

    const slice = walletBody.beginParse();
    if (slice.loadUint(32) !== WalletContractV5R1.OpCodes.auth_extension) return undefined;
    slice.loadUintBig(64); // query_id
    const finalAction = loadOutListExtendedV5R1(slice).at(-1);
    if (finalAction?.type !== 'sendMsg' || Number(finalAction.mode) !== MFA_REFILL_SEND_MODE) return undefined;

    const { outMsg } = finalAction;
    if (outMsg.info.type !== 'internal' || !outMsg.info.dest.equals(extensionAddress)) return undefined;
    if (outMsg.body.bits.length !== 0 || outMsg.body.refs.length !== 0) return undefined;

    return outMsg.info.value.coins === refillAmount ? refillAmount : undefined;
  } catch {
    return undefined;
  }
}

function hideMfaRefillActivity(activities: ApiActivity[], extensionAddress: Address, refillAmount: bigint | undefined) {
  if (refillAmount === undefined) return { activities, wasHidden: false };

  for (let index = activities.length - 1; index >= 0; index--) {
    const activity = activities[index];
    if (!isMfaRefillActivity(activity, extensionAddress, refillAmount)) continue;

    return {
      activities: activities.map((item, itemIndex) => itemIndex === index ? { ...item, shouldHide: true } : item),
      wasHidden: true,
    };
  }

  return { activities, wasHidden: false };
}

function isMfaRefillActivity(activity: ApiActivity, extensionAddress: Address, refillAmount: bigint) {
  if (activity.kind !== 'transaction' || activity.isIncoming || activity.slug !== TONCOIN.slug
    || activity.amount !== -refillAmount) {
    return false;
  }

  try {
    return Address.parse(activity.toAddress).equals(extensionAddress);
  } catch {
    return false;
  }
}

export async function emulateExtensionTransaction(
  payload: string,
  seedSignature: string,
  extensionAddress: Address,
  walletAddress: string,
  network?: ApiNetwork,
) {
  network ??= 'mainnet';
  ensureOpenContract(extensionAddress);

  const parsedPayload = Cell.fromBase64(payload);
  const parsedSignature = Buffer.from(seedSignature, 'base64');

  const { resultUnsafe } = await signCustomData(
    { user: { id: true } },
    parsedPayload.hash().toString('base64'),
    {
      shouldSignHash: true,
      isPayloadBinary: true,
    },
  );

  const parsedTelegramSignature = Buffer.from(resultUnsafe.signature, 'base64');

  const message = prepareMessage(
    parsedPayload,
    parsedSignature,
    parsedTelegramSignature,
    resultUnsafe.auth_date,
  );

  const externalMessage = external({ to: extensionAddress, body: message });
  const boc = beginCell()
    .store(storeMessage(externalMessage))
    .endCell()
    .toBoc()
    .toString('base64');
  const walletAddressFormatted = toBase64Address(Address.parse(walletAddress), false, network);
  const parsed = await callMfaApiWithThrow('emulateMfaMessage', network, walletAddressFormatted, boc);

  const { realFee, activities } = parsed;

  return {
    transfers: activities.filter((activity) => activity.fromAddress === walletAddressFormatted),
    realFee,
  };
}
