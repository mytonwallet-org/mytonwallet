import type { Address, Cell, Contract, ContractProvider, Sender } from '@ton/core';
import { beginCell, contractAddress, Dictionary, SendMode, toNano } from '@ton/core';

export const CANCEL_FEE = toNano('0.1');

export const Opcodes = {
  NFT_TRANSFER: 0x5fcc3d14,
  NFT_OWNERSHIP_ASSIGNED: 0x05138d91,
  SET_ACL: 0x996c7334,
  SUDOER_REQUEST: 0x5e2a5f0a,
  CREATE_CHECK: 0x6a3f7c7f,
  CASH_CHECK: 0x69e7ac28,
  CANCEL_CHECK: 0x4a1c5e3b,
};

export const Errors = {
  // op::set_jetton_wallets
  JETTON_WALLETS_ALREADY_SET: 400,
  UNAUTHORIZED_JETTON_WALLET: 401,
  MISSING_FORWARD_PAYLOAD: 402,
  INVALID_FORWARD_PAYLOAD: 403,
  INVALID_FORWARD_OPERATION: 404,

  // op::create_check error codes
  CHECK_ALREADY_EXISTS: 410,
  INSUFFICIENT_FUNDS: 411,

  // op::cash_check error codes
  CHECK_NOT_FOUND: 420,
  INVALID_RECEIVER_ADDRESS: 421,
  INCORRECT_SIGNATURE: 422,
  AUTH_DATE_TOO_OLD: 423,
  CHAT_INSTANCE_MISMATCH: 424,
  USERNAME_MISMATCH: 425,
  UNAUTHORIZED_SENDER: 430,
};

export type PushNftEscrowConfig = {
  instanceId: number;
  sudoer: Address;
};

export type NftCheckInfo = {
  withUsername: boolean;
  chatInstance?: string;
  username?: string;
  comment?: string;
  createdAt: number;
  senderAddress: Address;
  nftAddress: Address;
};

export const Fees = {
  NFT_CREATE_GAS: 3000000n, // 0.003 TON
  NFT_TRANSFER: 50000000n, // 0.05 TON
  NFT_CASH_GAS: 7000000n, // 0.007 TON
};

const ID_SIZE = 20;

export function pushNftEscrowConfigToCell(config: PushNftEscrowConfig): Cell {
  return beginCell()
    .storeUint(config.instanceId, 32)
    .storeAddress(config.sudoer)
    .storeDict(Dictionary.empty(Dictionary.Keys.Uint(32), Dictionary.Values.Cell()))
    .endCell();
}

export class PushNftEscrow implements Contract {
  constructor(
    readonly address: Address,
    readonly init?: { code: Cell; data: Cell },
  ) {}

  static createFromAddress(address: Address) {
    return new PushNftEscrow(address);
  }

  static createFromConfig(config: PushNftEscrowConfig, code: Cell, workchain = 0) {
    const data = pushNftEscrowConfigToCell(config);
    const init = { code, data };
    return new PushNftEscrow(contractAddress(workchain, init), init);
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

  static prepareCreateCheck(opts: { checkId: number; chatInstance?: string; username?: string; comment?: string }) {
    const withUsername = opts.username !== undefined;

    const cellBuilder = beginCell()
      .storeUint(Opcodes.CREATE_CHECK, 32)
      .storeUint(opts.checkId, ID_SIZE)
      .storeBit(withUsername)
      .storeStringRefTail(withUsername ? opts.username! : opts.chatInstance!)
      .storeStringRefTail(opts.comment ?? '');

    return cellBuilder.endCell();
  }

  static prepareCreateNftCheck(
    opts: {
      checkId: number;
      chatInstance?: string;
      username?: string;
      comment?: string;
    },
    prevOwner: Address,
  ) {
    return beginCell()
      .storeUint(Opcodes.NFT_OWNERSHIP_ASSIGNED, 32)
      .storeUint(0, 64)
      .storeAddress(prevOwner)
      .storeRef(PushNftEscrow.prepareCreateCheck(opts))
      .endCell();
  }

  static prepareCancelCheck(opts: { checkId: number }) {
    return beginCell().storeUint(Opcodes.CANCEL_CHECK, 32).storeUint(opts.checkId, ID_SIZE).endCell();
  }

  async sendCancelCheck(provider: ContractProvider, via: Sender, opts: { checkId: number }, overrideValue?: bigint) {
    await provider.internal(via, {
      value: overrideValue ?? CANCEL_FEE,
      body: PushNftEscrow.prepareCancelCheck(opts),
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

  async sendCashCheck(
    provider: ContractProvider,
    opts: {
      checkId: number;
      authDate: string;
      chatInstance?: string;
      username?: string;
      receiverAddress: Address;
      signature: Buffer;
    },
  ) {
    const messageBody = beginCell()
      .storeUint(Opcodes.CASH_CHECK, 32)
      .storeUint(opts.checkId, ID_SIZE)
      .storeStringRefTail(opts.authDate)
      .storeStringRefTail(opts.chatInstance || opts.username!)
      .storeAddress(opts.receiverAddress)
      .storeBuffer(opts.signature)
      .endCell();

    try {
      return await provider.external(messageBody);
    } catch (error: any) {
      const exitCode = error.exitCode || 500;
      const errorMessage = `External message not accepted by smart contract\nExit code: ${exitCode}`;
      throw new Error(errorMessage);
    }
  }

  async getCheckInfo(checkId: number): Promise<NftCheckInfo>;

  // This version is used directly with a provider
  async getCheckInfo(provider: ContractProvider, checkId: number): Promise<NftCheckInfo>;

  // Implementation handling both cases
  async getCheckInfo(providerOrCheckId: ContractProvider | number, maybeCheckId?: number): Promise<NftCheckInfo> {
    let provider: ContractProvider;
    let checkId: number;

    if (typeof providerOrCheckId === 'number') {
      provider = (this as any).provider;
      checkId = providerOrCheckId;
    } else {
      provider = providerOrCheckId;
      checkId = maybeCheckId as number;
    }

    const result = await provider.get('get_check_info', [{ type: 'int', value: BigInt(checkId) }]);

    const withUsername = result.stack.readBoolean();
    const chatOrUsername = result.stack.readCell().beginParse().loadStringTail();
    const chatInstance = withUsername ? undefined : chatOrUsername;
    const username = withUsername ? chatOrUsername : undefined;
    const comment = result.stack.readCell().beginParse().loadStringTail() || undefined;
    const createdAt = result.stack.readNumber();
    const senderAddress = result.stack.readAddress();
    const nftAddress = result.stack.readAddress();

    return {
      withUsername,
      chatInstance,
      username,
      comment,
      createdAt,
      senderAddress,
      nftAddress,
    };
  }
}
