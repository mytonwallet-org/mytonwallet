import type {
  Cell,
  Contract,
  ContractProvider,
} from '@ton/core';
import {
  Address,
  beginCell,
  contractAddress,
} from '@ton/core';

import { dnsCategoryToBigInt } from '../util/dns';
import { DnsCategory, DnsOpCode } from '../constants';

export type DnsItemConfig = object;

export function dnsItemConfigToCell(config: DnsItemConfig): Cell {
  return beginCell().endCell();
}

export class DnsItem implements Contract {
  constructor(
    readonly address: Address,
    readonly init?: { code: Cell; data: Cell },
  ) {}

  static createFromAddress(address: Address) {
    return new DnsItem(address);
  }

  static createFromConfig(config: DnsItemConfig, code: Cell, workchain = 0) {
    const data = dnsItemConfigToCell(config);
    const init = { code, data };
    return new DnsItem(contractAddress(workchain, init), init);
  }

  async getDomain(provider: ContractProvider) {
    const res = await provider.get('get_domain', []);
    const domain = res.stack.readString();
    return domain;
  }

  async getTelemintDomain(provider: ContractProvider) {
    const res = await provider.get('get_full_domain', []);
    // The contract returns the full domain with its parts in reverse order, separated by zero bytes: "me\0t\0alice\0"
    const parts = res.stack.readString().split('\0').filter(Boolean);
    parts.reverse();
    return parts.join('.');
  }

  async getNftData(provider: ContractProvider) {
    const res = await provider.get('get_nft_data', []);
    const isInitialized = res.stack.readBoolean();
    const index = res.stack.readBigNumber();
    const collectionAddress = res.stack.readAddressOpt();
    const owner = res.stack.readAddressOpt();

    return {
      isInitialized,
      index,
      collectionAddress,
      owner,
    };
  }

  async getLastFillUpTime(provider: ContractProvider): Promise<bigint> {
    const result = await provider.get('get_last_fill_up_time', []);
    return result.stack.readBigNumber();
  }

  static buildFillUpMessage(queryId?: bigint) {
    return DnsItem.buildDeleteDnsRecordMessage(queryId);
  }

  static buildDeleteDnsRecordMessage(queryId?: bigint, category?: string) {
    return beginCell()
      .storeUint(DnsOpCode.ChangeRecord, 32)
      .storeUint(queryId ?? 0n, 64)
      .storeUint(dnsCategoryToBigInt(category), 256)
      .endCell();
  }

  static buildChangeDnsWalletMessage(address: string, queryId?: bigint) {
    return beginCell()
      .storeUint(DnsOpCode.ChangeRecord, 32)
      .storeUint(queryId ?? 0n, 64)
      .storeUint(dnsCategoryToBigInt(DnsCategory.Wallet), 256)
      .storeRef(
        beginCell()
          .storeUint(0x9fd3, 16)
          .storeAddress(Address.parse(address))
          .storeUint(0, 8)
          .endCell(),
      )
      .endCell();
  }
}
