import type { MessageRelaxed } from '@ton/core';
import {
  beginCell, Cell, contractAddress, storeMessageRelaxed,
} from '@ton/core';
import { sign } from '@ton/crypto';

import { TELEGRAM_WALLET_MAX_MESSAGES } from '../constants';

export const TELEGRAM_WALLET_TRAMPOLINE_CODE_HASH
  = '9149ae51c1e4689710cebf7830297b16acfbadb363a920a537893e7ffeeca768';

const TELEGRAM_WALLET_TRAMPOLINE_CODE_BOC = Buffer.from(
  'b5ee9c7241010101001a000030ff00209821d7498308b9f240df8085f833d0ed1e20ed53d969427e39',
  'hex',
);

let telegramWalletTrampolineCode: Cell | undefined;

export function getTelegramWalletTrampolineCode() {
  telegramWalletTrampolineCode ??= Cell.fromBoc(TELEGRAM_WALLET_TRAMPOLINE_CODE_BOC)[0];

  return telegramWalletTrampolineCode;
}

const TELEGRAM_WALLET_REVISION = 0;
const TELEGRAM_WALLET_MAINNET_SUBWALLET_ID = 0x7FFF7F11;
const TELEGRAM_WALLET_TESTNET_SUBWALLET_ID = 0x7FFF7FFD;

const TELEGRAM_WALLET_SEND_ONE_EXTERNAL_OP = 0x63896E75;
const TELEGRAM_WALLET_SEND_BULK_EXTERNAL_OP = 0x73896E75;

type TelegramMessageToSend = {
  sendMode: number;
  messageCell: Cell;
};

type CreateTelegramWalletTransferOptions = {
  messages: MessageRelaxed[];
  sendMode: number;
  seqno: number;
  timeout?: number | null;
  secretKey: Buffer;
  authType?: 'internal' | 'external';
};

export class TelegramWallet {
  public readonly publicKey: Buffer;
  public readonly address;
  public readonly init: { code: Cell; data: Cell };

  private constructor(
    publicKey: Buffer,
    public readonly workchain: number,
    public readonly subwalletId: number,
  ) {
    this.publicKey = publicKey;
    this.init = {
      code: getTelegramWalletTrampolineCode(),
      data: buildTelegramWalletData(publicKey, subwalletId),
    };
    this.address = contractAddress(workchain, this.init);
  }

  static create(args: { publicKey: Buffer; workchain?: number; subwalletId: number }) {
    return new TelegramWallet(args.publicKey, args.workchain ?? 0, args.subwalletId);
  }

  createTransfer({
    messages,
    sendMode,
    seqno,
    timeout,
    secretKey,
    authType = 'external',
  }: CreateTelegramWalletTransferOptions) {
    if (authType !== 'external') {
      throw new Error(`Telegram wallet doesn't support authType "${authType}"`);
    }

    const toSend = messages.map((message) => ({
      sendMode,
      messageCell: beginCell().store(storeMessageRelaxed(message)).endCell(),
    }));

    const request = buildTelegramWalletExternalRequest({
      messages: toSend,
      seqno,
      subwalletId: this.subwalletId,
      validUntil: timeout ?? Math.round(Date.now() / 1000) + 60,
    });
    const signature = sign(request.hash(), secretKey);

    return beginCell()
      .storeBuffer(signature)
      .storeSlice(request.beginParse())
      .endCell();
  }
}

export function getTelegramWalletSubwalletId(isTestnetSubwalletId?: boolean) {
  return isTestnetSubwalletId ? TELEGRAM_WALLET_TESTNET_SUBWALLET_ID : TELEGRAM_WALLET_MAINNET_SUBWALLET_ID;
}

function buildTelegramWalletData(publicKey: Buffer, subwalletId: number) {
  if (publicKey.length !== 32) {
    throw new Error('Telegram wallet public key must be 32 bytes');
  }

  return beginCell()
    .storeUint(TELEGRAM_WALLET_REVISION, 8)
    .storeUint(0, 32)
    .storeUint(subwalletId, 32)
    .storeBuffer(publicKey)
    .endCell();
}

function buildTelegramWalletExternalRequest(args: {
  messages: TelegramMessageToSend[];
  seqno: number;
  subwalletId: number;
  validUntil: number;
}) {
  const {
    messages, seqno, subwalletId, validUntil,
  } = args;

  if (messages.length === 0) {
    throw new Error('Telegram wallet transfer requires at least one message');
  }
  if (messages.length > TELEGRAM_WALLET_MAX_MESSAGES) {
    throw new Error(`Telegram wallet supports at most ${TELEGRAM_WALLET_MAX_MESSAGES} messages`);
  }

  const body = beginCell()
    .storeUint(messages.length === 1 ? TELEGRAM_WALLET_SEND_ONE_EXTERNAL_OP : TELEGRAM_WALLET_SEND_BULK_EXTERNAL_OP, 32)
    .storeUint(subwalletId, 32)
    .storeUint(validUntil, 32)
    .storeUint(seqno, 32);

  if (messages.length === 1) {
    const [message] = messages;
    return body
      .storeUint(message.sendMode, 8)
      .storeRef(message.messageCell)
      .endCell();
  }

  return body
    .storeSlice(buildTelegramWalletMessageArray(messages).beginParse())
    .endCell();
}

function buildTelegramWalletMessageArray(messages: TelegramMessageToSend[]) {
  let nextChunk: Cell | undefined;
  let nextMessageIndex = messages.length;

  while (nextMessageIndex > 0) {
    const maxChunkSize = nextChunk ? 3 : 4;
    const chunkStart = Math.max(0, nextMessageIndex - maxChunkSize);
    const chunk = beginCell().storeMaybeRef(nextChunk);

    for (let i = chunkStart; i < nextMessageIndex; i++) {
      chunk
        .storeUint(messages[i].sendMode, 8)
        .storeRef(messages[i].messageCell);
    }

    nextChunk = chunk.endCell();
    nextMessageIndex = chunkStart;
  }

  return beginCell()
    .storeUint(messages.length, 8)
    .storeMaybeRef(nextChunk)
    .endCell();
}
