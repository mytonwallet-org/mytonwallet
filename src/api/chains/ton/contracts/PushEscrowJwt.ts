import type { Address, Cell, Contract, ContractProvider, Sender, Slice } from '@ton/core';
import { beginCell, contractAddress, Dictionary, SendMode } from '@ton/core';

const ID_SIZE = 20;
export const CANCEL_FEE = 100000000n;

export const Opcodes = {
  JETTON_TRANSFER: 0xf8a7ea5,
  JETTON_TRANSFER_NOTIFICATION: 0x7362d09c,
  SET_ACL: 0x996c7334,
  SUDOER_REQUEST: 0x5e2a5f0a,
  CREATE_CHECK: 0x6a3f7c7f,
  CASH_CHECK: 0x69e7ac28,
  CANCEL_CHECK: 0x4a1c5e3b,
  ADD_PUBKEY: 0x7d4b3e91,
  REMOVE_PUBKEY: 0x8f5c2a73,
};

export const Errors = {
  // op::set_jetton_wallets
  UNAUTHORIZED_SUDOER: 400,

  // op::create_check error codes
  CHECK_ALREADY_EXISTS: 410,
  INSUFFICIENT_FUNDS: 411,
  INVALID_PAYLOAD: 412,
  INVALID_OP: 413,
  MISSING_FORWARD_PAYLOAD: 414,

  // op::cash_check error codes
  CHECK_NOT_FOUND: 420,
  INVALID_RECEIVER_ADDRESS: 421,
  RECEIVER_ADDRESS_MISMATCH: 424,
  INCORRECT_PROOF: 422,
  AUTH_DATE_TOO_OLD: 423,
  TARGET_HASH3_MISMATCH: 425,
  UNAUTHORIZED_JETTON_WALLET: 426,
  PUBKEY_HASH_MISMATCH: 427,
  PUBKEY_NOT_FOUND: 428,
  INVALID_PUBKEY_INDEX: 429,
  PUBKEY_TOO_FRESH: 430,

  // op::cancel_check error codes
  UNAUTHORIZED_CANCEL: 440,
  INSUFFICIENT_CANCEL_FEE: 441,
};

export const Fees = {
  TON_CREATE_GAS: 6000000n, // 0.006 TON
  TON_CASH_GAS: 50000000n, // 0.05 TON
  TON_TRANSFER: 3000000n, // 0.003 TON
  TON_CANCEL: 100000000n, // 0.1 TON
  JETTON_CREATE_GAS: 7000000n, // 0.007 TON
  JETTON_CASH_GAS: 50000000n, // 0.05 TON
  JETTON_TRANSFER: 50000000n, // 0.05 TON
  TINY_JETTON_TRANSFER: 18000000n, // 0.018 TON
};

export function createDefaultPushEscrowJwtConfig(
  instanceId: number,
  sudoer: Address,
  pubkeyHashes?: bigint[],
): PushEscrowJwtConfig {
  return {
    instanceId,
    sudoer,
    pubkeyHashes,
  };
}

export type CheckInfo = {
  amount: bigint;
  jettonWalletAddress?: Address;
  salt: bigint;
  targetHash3: bigint;
  pubkeyIndices: number[];
  comment?: string;
  createdAt: number;
  senderAddress: Address;
};

export type PushEscrowJwtConfig = {
  instanceId: number;
  sudoer: Address;
  pubkeyHashes?: bigint[];
};

export function pushEscrowConfigToCell(config: PushEscrowJwtConfig): Cell {
  const checksDict = Dictionary.empty(Dictionary.Keys.Uint(32), Dictionary.Values.Cell());
  const pubkeysDict = Dictionary.empty<number, Slice>(Dictionary.Keys.Uint(16), {
    serialize: (src: Slice, builder) => {
      builder.storeSlice(src);
    },
    parse: (src) => src,
  });

  const checksDictLastIndex = config.pubkeyHashes?.length ?? 0;

  config.pubkeyHashes?.forEach((pubkeyHash, index) => {
    pubkeysDict.set(
      index + 1,
      beginCell()
        .storeUint(pubkeyHash, 256)
        .storeUint(Math.floor(Date.now() / 1000), 32)
        .endCell()
        .beginParse(),
    );
  });

  return beginCell()
    .storeUint(config.instanceId, 32)
    .storeAddress(config.sudoer)
    // eslint-disable-next-line no-null/no-null
    .storeAddress(null) // usdt_jetton_wallet (initially null)
    // eslint-disable-next-line no-null/no-null
    .storeAddress(null) // my_jetton_wallet (initially null)
    .storeDict(checksDict)
    .storeDict(pubkeysDict)
    .storeUint(checksDictLastIndex, 16)
    .endCell();
}

export class PushEscrowJwt implements Contract {
  constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {
  }

  static createFromAddress(address: Address) {
    return new PushEscrowJwt(address);
  }

  static createFromConfig(config: PushEscrowJwtConfig, code: Cell, workchain = 0) {
    const data = pushEscrowConfigToCell(config);
    const init = { code, data };

    return new PushEscrowJwt(contractAddress(workchain, init), init);
  }

  async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
    await provider.internal(via, {
      value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: beginCell().endCell(),
    });
  }

  async getBalance(provider: ContractProvider) {
    return (await provider.getState()).balance;
  }

  static prepareCreateCheck(
    opts: {
      checkId: number;
      salt: bigint;
      targetHash3: bigint;
      pubkeyIndices: number[];
      comment?: string;
    },
  ) {
    const cellBuilder = beginCell()
      .storeUint(Opcodes.CREATE_CHECK, 32)
      .storeUint(opts.checkId, ID_SIZE)
      .storeUint(opts.salt, 128)
      .storeUint(opts.targetHash3, 256)
      .storeUint(opts.pubkeyIndices.length, 5)
      .storeBuffer(packPubkeyIndices(opts.pubkeyIndices))
      .storeStringRefTail(opts.comment ?? '');

    return cellBuilder.endCell();
  }

  async sendCreateCheck(
    provider: ContractProvider,
    via: Sender,
    opts: {
      checkId: number;
      salt: bigint;
      targetHash3: bigint;
      pubkeyIndices: number[];
      comment?: string;
      value: bigint;
    },
  ) {
    const body = PushEscrowJwt.prepareCreateCheck(opts);

    await provider.internal(via, {
      value: opts.value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body,
    });
  }

  static prepareCreateJettonCheck(
    opts: {
      checkId: number;
      amount: bigint;
      salt: bigint;
      targetHash3: bigint;
      pubkeyIndices: number[];
      comment?: string;
    },
    originalSenderAddress: Address,
  ) {
    return beginCell()
      .storeUint(Opcodes.JETTON_TRANSFER_NOTIFICATION, 32)
      .storeUint(0, 64) // query_id
      .storeCoins(opts.amount)
      .storeAddress(originalSenderAddress)
      .storeRef(PushEscrowJwt.prepareCreateJettonCheckForwardPayload(opts))
      .endCell();
  }

  static prepareCreateJettonCheckForwardPayload(
    opts: {
      checkId: number;
      salt: bigint;
      targetHash3: bigint;
      pubkeyIndices: number[];
      comment?: string;
    },
  ) {
    return PushEscrowJwt.prepareCreateCheck(opts);
  }

  async sendCashCheck(
    provider: ContractProvider,
    opts: {
      checkId: number;
      receiverAddress: Address;
      pubkeyIndex: number;
      publicSignals: {
        expiresAt: bigint;
        targetHash2: bigint;
        pubkeyHash: bigint;
        receiverAddressHashHead: bigint;
      };
      proof: {
        pi_a: Buffer;
        pi_b: Buffer;
        pi_c: Buffer;
      };
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.CASH_CHECK, 32)
      .storeUint(opts.checkId, ID_SIZE)
      .storeAddress(opts.receiverAddress)
      .storeUint(opts.pubkeyIndex, 4)
      .storeRef(
        beginCell()
          .storeUint(opts.publicSignals.expiresAt, 32)
          .storeUint(opts.publicSignals.targetHash2, 256)
          .storeUint(opts.publicSignals.pubkeyHash, 256)
          .storeUint(opts.publicSignals.receiverAddressHashHead, 256)
          .endCell(),
      )
      .storeRef(beginCell().storeBuffer(opts.proof.pi_a).endCell())
      .storeRef(beginCell().storeBuffer(opts.proof.pi_b).endCell())
      .storeRef(beginCell().storeBuffer(opts.proof.pi_c).endCell())
      .endCell();

    try {
      return await provider.external(messageBody);
    } catch (error: any) {
      const exitCode = error.exitCode || 500;
      const errorMessage = `External message not accepted by smart contract\nExit code: ${exitCode}`;
      throw new Error(errorMessage);
    }
  }

  async sendCancelCheck(
    provider: ContractProvider,
    via: Sender,
    opts: {
      checkId: number;
    },
    overrideValue?: bigint,
  ) {
    await provider.internal(via, {
      value: overrideValue ?? CANCEL_FEE,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: PushEscrowJwt.prepareCancelCheck(opts),
    });
  }

  static prepareCancelCheck(opts: { checkId: number }) {
    return beginCell()
      .storeUint(Opcodes.CANCEL_CHECK, 32)
      .storeUint(opts.checkId, ID_SIZE)
      .endCell();
  }

  async sendSetAcl(
    provider: ContractProvider,
    via: Sender,
    opts: {
      sudoer: Address | null;
      usdtJettonWallet: Address | null;
      myJettonWallet: Address | null;
      value: bigint;
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.SET_ACL, 32)
      .storeAddress(opts.sudoer)
      .storeAddress(opts.usdtJettonWallet)
      .storeAddress(opts.myJettonWallet)
      .endCell();

    await provider.internal(via, {
      value: opts.value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: messageBody,
    });
  }

  async sendSudoerRequest(
    provider: ContractProvider,
    via: Sender,
    opts: {
      message: Cell;
      mode: number;
      value: bigint;
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.SUDOER_REQUEST, 32)
      .storeRef(opts.message)
      .storeUint(opts.mode, 8)
      .endCell();

    await provider.internal(via, {
      value: opts.value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: messageBody,
    });
  }

  // Used by `SandboxContract`
  async getCheckInfo(checkId: number): Promise<CheckInfo>;

  // Used directly with a provider
  async getCheckInfo(provider: ContractProvider, checkId: number): Promise<CheckInfo>;

  async getCheckInfo(providerOrCheckId: ContractProvider | number, maybeCheckId?: number): Promise<CheckInfo> {
    let provider: ContractProvider;
    let checkId: number;

    if (typeof providerOrCheckId === 'number') {
      provider = (this as any).provider;
      checkId = providerOrCheckId;
    } else {
      provider = providerOrCheckId;
      checkId = maybeCheckId as number;
    }

    const result = await provider.get('get_check_info', [
      { type: 'int', value: BigInt(checkId) },
    ]);

    const amount = result.stack.readBigNumber();
    const jettonWalletAddress = result.stack.readCellOpt()?.beginParse().loadAddress();
    const salt = result.stack.readBigNumber();
    const targetHash3 = result.stack.readBigNumber();
    const pubkeyIndices = unpackPubkeyIndicesCell(result.stack.readNumber(), result.stack.readCell());
    const commentCell = result.stack.readCell();
    const comment = commentCell.beginParse().loadStringTail() || undefined;
    const createdAt = result.stack.readNumber();
    const senderAddress = result.stack.readCell().beginParse().loadAddress();

    return {
      amount,
      jettonWalletAddress,
      salt,
      targetHash3,
      pubkeyIndices,
      comment,
      createdAt,
      senderAddress,
    };
  }

  async sendAddPubkey(
    provider: ContractProvider,
    via: Sender,
    opts: {
      pubkeyHash: bigint;
      value: bigint;
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.ADD_PUBKEY, 32)
      .storeUint(opts.pubkeyHash, 256)
      .endCell();

    await provider.internal(via, {
      value: opts.value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: messageBody,
    });
  }

  async sendRemovePubkey(
    provider: ContractProvider,
    via: Sender,
    opts: {
      index: number;
      value: bigint;
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.REMOVE_PUBKEY, 32)
      .storeUint(opts.index, 16)
      .endCell();

    await provider.internal(via, {
      value: opts.value,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      body: messageBody,
    });
  }

  // Get method to retrieve pubkeys dictionary and last index - this version is used by `SandboxContract`
  async getPubkeys(): Promise<{ dict: Record<number, { hash: bigint; addedAt: number }>; lastIndex: number }>;

  // This version is used directly with a provider
  async getPubkeys(provider: ContractProvider): Promise<{
    dict: Record<number, { hash: bigint; addedAt: number }>;
    lastIndex: number;
  }>;

  // Implementation handling both cases
  async getPubkeys(maybeProvider?: ContractProvider): Promise<{
    dict: Record<number, { hash: bigint; addedAt: number }>;
    lastIndex: number;
  }> {
    const provider = maybeProvider || (this as any).provider;

    const result = await provider.get('get_pubkeys', []);
    const tonDict = Dictionary.loadDirect(Dictionary.Keys.Uint(16), {
      parse: (src) => {
        const hash = src.loadUintBig(256);
        const addedAt = src.loadUint(32);
        return { hash, addedAt };
      },
      serialize: () => undefined,
    }, result.stack.readCell());
    const lastIndex = result.stack.readNumber();

    const dict: Record<number, { hash: bigint; addedAt: number }> = {};
    for (const [key, value] of tonDict) {
      dict[key] = value;
    }

    return { dict, lastIndex };
  }
}

export function packPubkeyIndices(indices: number[]): Buffer {
  const buffer = Buffer.alloc(indices.length * 2); // 16 bits = 2 bytes per index

  for (let i = 0; i < indices.length; i++) {
    buffer.writeUInt16BE(indices[i], i * 2);
  }

  return buffer;
}

export function unpackPubkeyIndicesCell(pubkeyIndicesCount: number, pubkeyIndicesCell: Cell) {
  const pubkeyIndices: number[] = [];
  const indicesSlice = pubkeyIndicesCell.beginParse();

  for (let i = 0; i < pubkeyIndicesCount; i++) {
    pubkeyIndices.push(indicesSlice.loadUint(16));
  }

  return pubkeyIndices;
}
