import type { OpenedContract } from '@ton/core';
import {
  Address, beginCell, Cell, Dictionary,
  external, loadMessageRelaxed, storeMessage, storeMessageRelaxed,
} from '@ton/core';

import type { ApiEmulationResult, ApiNetwork } from '../../api/types';

import { signCustomData } from '../../util/authApi/telegram';
import { WORKCHAIN } from '../../api/chains/ton/constants';
import { getExternalMsgHashNormalized } from '../../api/chains/ton/util/sendExternal';
import { getTonClient, toBase64Address } from '../../api/chains/ton/util/tonCore';
import { callMfaApiWithThrow } from '../api/connector';

import { MfaExtension, OpCode, prepareMessage } from '../../api/chains/ton/contracts/MfaExtension';

const NETWORK = 'mainnet';
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

  return await emulatePayload(payload, address, extensionAddress);
}

export async function emulatePayload(
  rawPayload: string,
  address: string,
  extensionAddress: Address,
): Promise<Pick<ApiEmulationResult, 'activities' | 'realFee'>> {
  const message = Cell.fromBase64(rawPayload).beginParse();
  const outAction = message.loadRef().beginParse();
  const messageToWallet = outAction.loadRef();

  // patch message (add src)
  const messageRelaxed = loadMessageRelaxed(messageToWallet.beginParse());
  messageRelaxed.info.src = extensionAddress;

  const boc = beginCell().store(storeMessageRelaxed(messageRelaxed)).endCell()
    .toBoc()
    .toString('base64');
  const parsed = await callMfaApiWithThrow('emulateMfaMessage', NETWORK, address, boc);

  return {
    activities: parsed.activities,
    realFee: parsed.realFee,
  };
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
