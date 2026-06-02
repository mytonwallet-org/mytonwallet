import type {
  Address, Contract, ContractProvider, MessageRelaxed, Sender } from '@ton/core';
import { Cell } from '@ton/core';
import {
  beginCell,
  contractAddress,
  SendMode,
  storeMessageRelaxed,
} from '@ton/core';

import { MFA_EXTENSION_CODE_HASH } from '../../../../config';

export type MfaExtensionConfig = {
  telegramId: string;
  walletAddress: Address;
  seedPubkey: Buffer;
};

export enum OpCode {
  INSTALL = 0x43563174,
  INTERNAL_SIGNED = 0x53684037,
  SEND_ACTIONS = 0xb15f2c8c,
  REMOVE_EXTENSION = 0xaeb09887,
  RECOVERY = 0x8d9e73f8,
  CANCEL_RECOVERY = 0xd9cef94,
}

export function mfaExtensionConfigToCell(config: MfaExtensionConfig): Cell {
  return beginCell()
    .storeUint(0, 32)
    .storeAddress(config.walletAddress)
    .storeStringRefTail(config.telegramId)
    .storeBuffer(config.seedPubkey)
    .storeUint(0, 1 + 64)
    .endCell();
}

interface SeedSignatureAuth {
  seqno: number;
  signature: Buffer;
  validUntil: number;
}

interface DefaultSignaturesAuth {
  authDate: number;
  seqno: number;
  opCode: OpCode;
  payload: Cell;

  signature: Buffer;
  seedSignature: Buffer;
}

export class MfaExtension implements Contract {
  constructor(
    readonly address: Address,
    readonly init?: { code: Cell; data: Cell },
  ) {}

  static createFromAddress(address: Address) {
    return new MfaExtension(address);
  }

  static createFromConfig(config: MfaExtensionConfig, code: Cell, workchain = 0) {
    const data = mfaExtensionConfigToCell(config);
    const init = { code, data };
    return new MfaExtension(contractAddress(workchain, init), init);
  }

  async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
    await provider.internal(via, {
      value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: beginCell().storeUint(OpCode.INSTALL, 32).endCell(),
    });
  }

  async sendRemoveExtension(
    provider: ContractProvider,
    opts: {
      authDate: number;
      signature: Buffer;
      seedSignature: Buffer;
      seqno: number;
    },
  ) {
    const body = prepareBody({ ...opts, opCode: OpCode.REMOVE_EXTENSION, payload: beginCell().endCell() });
    await provider.external(body);
  }

  async sendSendActions(
    provider: ContractProvider,
    opts: {
      authDate: number;
      signature: Buffer;
      seedSignature: Buffer;
      seqno: number;
      payload: Cell;
    },
  ) {
    const body = prepareBody({ ...opts, opCode: OpCode.SEND_ACTIONS });

    await provider.external(body);
  }

  async sendActionsInternal(
    provider: ContractProvider,
    via: Sender,
    value: bigint,
    opts: {
      authDate: number;
      signature: Buffer;
      seedSignature: Buffer;
      seqno: number;
      payload: Cell;
    },
  ) {
    const body = beginCell()
      .storeUint(OpCode.INTERNAL_SIGNED, 32)
      .storeSlice(prepareBody({ ...opts, opCode: OpCode.SEND_ACTIONS }).beginParse())
      .endCell();

    await provider.internal(via, {
      value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body,
    });
  }

  async sendRecovery(provider: ContractProvider, opts: SeedSignatureAuth) {
    await provider.external(prepareSeedAuthWithSignatureBody(OpCode.RECOVERY, opts));
  }

  async sendCancelRecovery(provider: ContractProvider, opts: SeedSignatureAuth) {
    await provider.external(prepareSeedAuthWithSignatureBody(OpCode.CANCEL_RECOVERY, opts));
  }

  async sendExternalMessage(provider: ContractProvider, message: Cell) {
    await provider.external(message);
  }

  async getRecoveryState(provider: ContractProvider): Promise<{ isRecoveryStarted: boolean; blockedUntil: number }> {
    const { stack } = await provider.get('get_recovery_state', []);

    return {
      isRecoveryStarted: stack.readBoolean(),
      blockedUntil: stack.readNumber(),
    };
  }

  async getSeqno(provider: ContractProvider): Promise<number> {
    const { stack } = await provider.get('get_seqno', []);
    return stack.readNumber();
  }

  async getTelegramId(provider: ContractProvider): Promise<string> {
    const { stack } = await provider.get('get_telegram_id', []);
    return stack.readBigNumber().toString();
  }
}

export function prepareBodyWithoutSignature({
  opCode,
  seqno,
  payload,
}: Omit<DefaultSignaturesAuth, 'signature' | 'seedSignature' | 'authDate'>) {
  return beginCell()
    .storeUint(opCode, 32)
    .storeUint(seqno, 32)
    .storeRef(payload)
    .endCell();
}

export function getBodyFromRequest(seqno: number, message: MessageRelaxed) {
  const payload = beginCell()
    .storeUint(SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS, 8)
    .storeRef(beginCell().store(storeMessageRelaxed(message)).endCell())
    .endCell();

  return prepareBodyWithoutSignature({ opCode: OpCode.SEND_ACTIONS, payload, seqno });
}

export function prepareBody(opts: DefaultSignaturesAuth) {
  const { authDate, signature, seedSignature } = opts;

  const seedSignatureCell = beginCell().storeBuffer(seedSignature).endCell();

  return beginCell()
    .storeRef(seedSignatureCell)
    .storeStringRefTail(String(authDate))
    .storeSlice(prepareBodyWithoutSignature(opts).beginParse())
    .storeBuffer(signature)
    .endCell();
}

export function prepareMessage(payload: Cell, signature: Buffer, telegramSignature: Buffer, authDate: string) {
  return beginCell()
    .storeRef(beginCell().storeBuffer(signature).endCell())
    .storeStringRefTail(authDate)
    .storeSlice(payload.beginParse())
    .storeBuffer(telegramSignature)
    .endCell();
}

export function prepareSeedAuthBody(opCode: number, opts: Omit<SeedSignatureAuth, 'signature'>) {
  return beginCell().storeUint(opCode, 32).storeUint(opts.seqno, 32).storeUint(opts.validUntil, 32);
}

export function prepareSeedAuthWithSignatureBody(opCode: number, opts: SeedSignatureAuth) {
  return prepareSeedAuthBody(opCode, opts).storeBuffer(opts.signature).endCell();
}

export function getContractCode() {
  const libPrep = beginCell().storeUint(2, 8).storeBuffer(Buffer.from(MFA_EXTENSION_CODE_HASH, 'hex')).endCell();
  return new Cell({ exotic: true, bits: libPrep.bits, refs: libPrep.refs });
}
