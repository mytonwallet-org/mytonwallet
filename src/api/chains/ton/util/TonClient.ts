import type {
  Address, Contract, ContractProvider, ContractState, OpenedContract, Sender, StateInit, TupleItem,
} from '@ton/core';
import {
  beginCell, Cell, comment, external, openContract, storeMessage, toNano, TupleReader,
} from '@ton/core';

import type { FetchDemand } from '../../../../util/fetchDemand';
import type { GetAddressInfoResponse } from '../types';

import { fetchWithRetry } from '../../../../util/fetch';
import { ApiServerError } from '../../../errors';

export type TonClientParameters = {
  endpoint: string;
  apiKey?: string;
  headers?: AnyLiteral;
};

type ContractStateResult = {
  balance: bigint;
  extra_currencies?: { id: number; amount: string }[];
  state: 'active' | 'uninitialized' | 'frozen';
  code: Buffer | null;
  data: Buffer | null;
  lastTransaction: { lt: string; hash: string } | null;
};

/**
 * TonCenter v2 JSON-RPC client.
 *
 * Replaces `TonClient` from `@ton/ton`, whose `HttpApi` brings axios, zod and dataloader along for a
 * transport this project overrides anyway — every request here goes through `fetchWithRetry`. Only the
 * surface the wallet uses is implemented: get methods, contract state and fee estimation. `@ton/core`
 * supplies the contract and tuple primitives, so the wallet contract classes from `@ton/ton` keep working
 * against providers created here.
 */
export class TonClient {
  readonly parameters: TonClientParameters;

  private readonly demand?: FetchDemand;

  constructor(parameters: TonClientParameters, demand?: FetchDemand) {
    this.parameters = parameters;
    this.demand = demand;
  }

  /** A client whose requests, including the ones of the contracts it opens, are made on behalf of `demand` */
  withDemand(demand?: FetchDemand) {
    return demand && demand !== this.demand ? new TonClient(this.parameters, demand) : this;
  }

  getAddressInfo(address: string): Promise<GetAddressInfoResponse> {
    return this.callRpc('getAddressInformation', { address });
  }

  callRpc(method: string, params: any): Promise<any> {
    return this.sendRequest(this.parameters.endpoint, {
      id: 1, jsonrpc: '2.0', method, params,
    });
  }

  async sendFile(src: Buffer | string): Promise<void> {
    const boc = typeof src === 'object' ? src.toString('base64') : src;
    await this.callRpc('sendBocReturnHashNoError', { boc });
  }

  async sendRequest(apiUrl: string, request: any) {
    const method: string = request.method;

    const headers: AnyLiteral = {
      ...this.parameters.headers,
      'Content-Type': 'application/json',
    };
    if (this.parameters.apiKey) {
      headers['X-API-Key'] = this.parameters.apiKey;
    }
    const body = JSON.stringify(request);

    const response = await fetchWithRetry(apiUrl, {
      method: 'POST',
      body,
      headers,
    }, {
      shouldSkipRetryFn: (message, statusCode) => isNotTemporaryError(method, message, statusCode),
      demand: this.demand,
    });

    const data = await response.json();
    if (data.error) {
      throw new ApiServerError(getJsonRpcErrorMessage(data.error));
    }

    return data.result;
  }

  /** Runs a get method, throwing on a non-zero exit code. */
  async runMethod(address: Address, name: string, stack: TupleItem[] = []) {
    const result = await this.runGetMethod(address, name, stack);
    if (result.exit_code !== 0) {
      throw new Error(`Unable to execute get method. Got exit_code: ${result.exit_code}`);
    }

    return { gas_used: result.gas_used, stack: parseStack(result.stack) };
  }

  /** Runs a get method, reporting the exit code instead of throwing. */
  async runMethodWithError(address: Address, name: string, params: TupleItem[] = []) {
    const result = await this.runGetMethod(address, name, params);

    return { gas_used: result.gas_used, stack: parseStack(result.stack), exit_code: result.exit_code };
  }

  callGetMethod(address: Address, name: string, stack: TupleItem[] = []) {
    return this.runMethod(address, name, stack);
  }

  async getContractState(address: Address): Promise<ContractStateResult> {
    const info = await this.getAddressInfo(address.toString());

    return {
      balance: BigInt(info.balance),
      extra_currencies: (info as AnyLiteral).extra_currencies,
      state: info.state,
      // eslint-disable-next-line no-null/no-null
      code: info.code !== '' ? Buffer.from(info.code, 'base64') : null,
      // eslint-disable-next-line no-null/no-null
      data: info.data !== '' ? Buffer.from(info.data, 'base64') : null,
      lastTransaction: info.last_transaction_id.lt !== '0' ? {
        lt: info.last_transaction_id.lt,
        hash: info.last_transaction_id.hash,
      // eslint-disable-next-line no-null/no-null
      } : null,
    };
  }

  async isContractDeployed(address: Address) {
    return (await this.getContractState(address)).state === 'active';
  }

  async estimateExternalMessageFee(address: Address, args: {
    body: Cell;
    initCode: Cell | null;
    initData: Cell | null;
    ignoreSignature: boolean;
  }) {
    return this.callRpc('estimateFee', {
      address: address.toString(),
      body: args.body.toBoc().toString('base64'),
      init_data: args.initData ? args.initData.toBoc().toString('base64') : '',
      init_code: args.initCode ? args.initCode.toBoc().toString('base64') : '',
      ignore_chksig: args.ignoreSignature,
    });
  }

  open<T extends Contract>(src: T): OpenedContract<T> {
    return openContract(src, (args) => this.provider(args.address, args.init));
  }

  provider(address: Address, init?: StateInit | null): ContractProvider {
    // eslint-disable-next-line no-null/no-null
    return createProvider(this, address, init ?? null);
  }

  private runGetMethod(address: Address, method: string, stack: TupleItem[]) {
    return this.callRpc('runGetMethod', {
      address: address.toString(),
      method,
      stack: serializeStack(stack),
    });
  }
}

function createProvider(client: TonClient, address: Address, init: StateInit | null): ContractProvider {
  return {
    async getState(): Promise<ContractState> {
      const state = await client.getContractState(address);
      const last = state.lastTransaction
        ? { lt: BigInt(state.lastTransaction.lt), hash: Buffer.from(state.lastTransaction.hash, 'base64') }
        // eslint-disable-next-line no-null/no-null
        : null;

      let storage: ContractState['state'];
      if (state.state === 'active') {
        storage = { type: 'active', code: state.code, data: state.data };
      } else if (state.state === 'uninitialized') {
        storage = { type: 'uninit' };
      } else if (state.state === 'frozen') {
        storage = { type: 'frozen', stateHash: Buffer.alloc(0) };
      } else {
        throw new Error('Unsupported state');
      }

      // eslint-disable-next-line no-null/no-null
      let extracurrency: Record<number, bigint> | null = null;
      if (state.extra_currencies?.length) {
        extracurrency = {};
        for (const ec of state.extra_currencies) {
          extracurrency[ec.id] = BigInt(ec.amount);
        }
      }

      return {
        balance: state.balance, extracurrency, last, state: storage,
      };
    },

    async get(name, args) {
      if (typeof name !== 'string') {
        throw new Error('Method name must be a string for TonClient provider');
      }

      const method = await client.runMethod(address, name, args);
      return { stack: method.stack };
    },

    async external(message) {
      // eslint-disable-next-line no-null/no-null
      let neededInit: StateInit | null = null;
      if (init && !await client.isContractDeployed(address)) {
        neededInit = init;
      }

      const ext = external({ to: address, init: neededInit, body: message });
      const boc = beginCell().store(storeMessage(ext)).endCell().toBoc();
      await client.sendFile(boc);
    },

    async internal(via: Sender, message) {
      // eslint-disable-next-line no-null/no-null
      let neededInit: StateInit | null = null;
      if (init && !await client.isContractDeployed(address)) {
        neededInit = init;
      }

      const bounce = message.bounce ?? true;
      const value = typeof message.value === 'string' ? toNano(message.value) : message.value;
      // eslint-disable-next-line no-null/no-null
      const body = typeof message.body === 'string' ? comment(message.body) : (message.body ?? null);

      await via.send({
        to: address,
        value,
        bounce,
        sendMode: message.sendMode,
        extracurrency: message.extracurrency,
        init: neededInit,
        body,
      });
    },

    open(contract) {
      // eslint-disable-next-line no-null/no-null
      return openContract(contract, (args) => createProvider(client, args.address, args.init ?? null));
    },

    getTransactions() {
      throw new Error('getTransactions is not supported by this provider');
    },
  };
}

function serializeStack(src: TupleItem[]) {
  return src.map((item) => {
    switch (item.type) {
      case 'int':
        return ['num', item.value.toString()];
      case 'cell':
        return ['tvm.Cell', item.cell.toBoc().toString('base64')];
      case 'slice':
        return ['tvm.Slice', item.cell.toBoc().toString('base64')];
      case 'builder':
        return ['tvm.Builder', item.cell.toBoc().toString('base64')];
      default:
        throw new Error(`Unsupported stack item type: ${item.type}`);
    }
  });
}

function parseStackEntry(x: AnyLiteral): any {
  switch (x['@type']) {
    case 'tvm.list':
    case 'tvm.tuple':
      return x.elements.map(parseStackEntry);
    case 'tvm.cell':
    case 'tvm.slice':
      return Cell.fromBoc(Buffer.from(x.bytes, 'base64'))[0];
    case 'tvm.stackEntryCell':
      return parseStackEntry(x.cell);
    case 'tvm.stackEntrySlice':
      return parseStackEntry(x.slice);
    case 'tvm.stackEntryTuple':
      return parseStackEntry(x.tuple);
    case 'tvm.stackEntryList':
      return parseStackEntry(x.list);
    case 'tvm.stackEntryNumber':
      return parseStackEntry(x.number);
    case 'tvm.numberDecimal':
      return BigInt(x.number);
    default:
      throw new Error(`Unsupported item type: ${x['@type']}`);
  }
}

function parseStackItem(s: any[]): TupleItem {
  switch (s[0]) {
    case 'num': {
      const value: string = s[1];
      return value.startsWith('-')
        ? { type: 'int', value: -BigInt(value.slice(1)) }
        : { type: 'int', value: BigInt(value) };
    }
    case 'null':
      return { type: 'null' };
    case 'cell':
      return { type: 'cell', cell: Cell.fromBoc(Buffer.from(s[1].bytes, 'base64'))[0] };
    case 'slice':
      return { type: 'slice', cell: Cell.fromBoc(Buffer.from(s[1].bytes, 'base64'))[0] };
    case 'builder':
      return { type: 'builder', cell: Cell.fromBoc(Buffer.from(s[1].bytes, 'base64'))[0] };
    case 'tuple':
    case 'list':
      return s[1].elements.length === 0
        ? { type: 'null' }
        : { type: 'tuple', items: s[1].elements.map(parseStackEntry) };
    default:
      throw new Error(`Unsupported stack item type: ${s[0]}`);
  }
}

function parseStack(src: any[][]) {
  return new TupleReader(src.map(parseStackItem));
}

function getJsonRpcErrorMessage(error: unknown) {
  if (typeof error === 'string') {
    return error;
  }

  if (error && typeof error === 'object' && 'message' in error) {
    return String(error.message);
  }

  return JSON.stringify(error);
}

function isNotTemporaryError(method: string, message?: string, statusCode?: number) {
  return Boolean(statusCode === 422 || message?.match(/(exit code|exitcode=|duplicate message|too old seqno)/i));
}
