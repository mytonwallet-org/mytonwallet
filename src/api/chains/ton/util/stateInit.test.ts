import type { SimpleLibrary, StateInit } from '@ton/core';
import {
  Address, beginCell, contractAddress, Dictionary, loadSimpleLibrary, storeSimpleLibrary, storeStateInit,
} from '@ton/core';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import { ContractType, KnownContracts } from '../constants';
import * as knownContracts from './knownContracts';
import { parseStateInit } from './stateInit';

const w5 = WalletContractV5R1.create({ workchain: 0, publicKey: Buffer.alloc(32) });
const otherAddress = WalletContractV5R1.create({ workchain: 0, publicKey: Buffer.alloc(32, 1) }).address;

function toBase64(stateInit: StateInit) {
  return beginCell().store(storeStateInit(stateInit)).endCell().toBoc().toString('base64');
}

function flipBit(hash: Buffer, bit: number) {
  const result = Buffer.from(hash);
  result[bit >> 3] ^= 0x80 >> (bit & 7);
  return result;
}

describe('parseStateInit', () => {
  it('names a known wallet deployed to the recipient address', () => {
    expect(parseStateInit(toBase64(w5.init), w5.address.toString())).toEqual({
      walletName: 'W5',
      isDeployable: true,
    });
  });

  it('accepts the recipient in the raw form a dApp may send', () => {
    expect(parseStateInit(toBase64(w5.init), w5.address.toRawString())?.isDeployable).toBe(true);
  });

  it('tells a StateInit that belongs to another address', () => {
    expect(parseStateInit(toBase64(w5.init), otherAddress.toString())).toEqual({
      walletName: 'W5',
      isDeployable: false,
    });
  });

  it('leaves unknown code unnamed', () => {
    const stateInit = { code: beginCell().storeUint(0xdeadbeef, 32).endCell(), data: beginCell().endCell() };

    expect(parseStateInit(toBase64(stateInit), contractAddress(0, stateInit).toString())).toEqual({
      isDeployable: true,
    });
  });

  it('leaves a known contract that is not a wallet unnamed', () => {
    jest.spyOn(knownContracts, 'findKnownContract').mockReturnValueOnce(KnownContracts.dedustV2Cpmm);

    expect(parseStateInit(toBase64(w5.init), w5.address.toString())).toEqual({
      isDeployable: true,
    });
  });

  it('names every known wallet the way users know it', () => {
    const findKnownContract = jest.spyOn(knownContracts, 'findKnownContract');
    const names = Object.values(KnownContracts)
      .filter(({ type }) => type === ContractType.Wallet)
      .map((contract) => {
        findKnownContract.mockReturnValueOnce(contract);
        return parseStateInit(toBase64(w5.init), w5.address.toString())?.walletName;
      });

    expect(names).toEqual([
      'v1R1', 'v1R2', 'v1R3', 'v2R1', 'v2R2', 'v3R1', 'v3R2', 'v4R1', 'v4R2', 'W5',
      'Telegram', 'Highload v2', 'Multisig', 'Multisig', 'Vesting', 'Multisig',
    ]);
  });

  it('judges the address by the StateInit as signed, without bits that do not belong to it', () => {
    const cell = beginCell().store(storeStateInit(w5.init)).storeUint(1, 1).endCell();

    expect(parseStateInit(cell.toBoc().toString('base64'), w5.address.toString())?.isDeployable).toBe(true);
  });

  it('skips the address prefix that a fixed prefix length leaves to the shard', () => {
    const stateInit = { ...w5.init, splitDepth: 8 };
    const { hash } = contractAddress(0, stateInit);
    const toAddress = (bit: number) => new Address(0, flipBit(hash, bit)).toString();

    expect(parseStateInit(toBase64(stateInit), toAddress(7))?.isDeployable).toBe(true);
    expect(parseStateInit(toBase64(stateInit), toAddress(8))?.isDeployable).toBe(false);
  });

  it('refuses a fixed prefix longer than the network allows', () => {
    const stateInit = { ...w5.init, splitDepth: 9 };

    expect(parseStateInit(toBase64(stateInit), contractAddress(0, stateInit).toString())?.isDeployable).toBe(false);
  });

  it('refuses a StateInit that carries libraries', () => {
    const libraries = Dictionary.empty<bigint, SimpleLibrary>(Dictionary.Keys.BigUint(256), {
      serialize: (library, builder) => builder.store(storeSimpleLibrary(library)),
      parse: loadSimpleLibrary,
    });
    const root = beginCell().storeUint(1, 8).endCell();
    libraries.set(BigInt(`0x${root.hash().toString('hex')}`), { public: true, root });
    const stateInit = { ...w5.init, libraries };

    expect(parseStateInit(toBase64(stateInit), contractAddress(0, stateInit).toString())?.isDeployable).toBe(false);
  });

  it('gives nothing for data that is not a StateInit', () => {
    expect(parseStateInit(beginCell().endCell().toBoc().toString('base64'), w5.address.toString())).toBeUndefined();
    expect(parseStateInit('not a boc', w5.address.toString())).toBeUndefined();
  });
});
