import type { ContractProvider, TupleItem } from '@ton/core';
import {
  Address,
  beginCell,
  Cell,
  TupleReader,
} from '@ton/core';

import { DnsItem } from './DnsItem';

const ITEM_ADDRESS = Address.parse('EQC0AmhJ0wYS4QCfZrCqtZ-kwLbEDtbkJaRBlMRcgHMNJSas');
const COLLECTION_ADDRESS = Address.parse('EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz');
const OWNER_ADDRESS = Address.parse('UQDYzZmfsrGzhObKJUw4gzdeIxEai3jAFbiGKGwxvxHinf4K');

describe('getNftData', () => {
  it('reads the standard get_nft_data stack', async () => {
    const provider = mockProvider({
      get_nft_data: [
        { type: 'int', value: -1n },
        { type: 'int', value: 42n },
        { type: 'slice', cell: beginCell().storeAddress(COLLECTION_ADDRESS).endCell() },
        { type: 'slice', cell: beginCell().storeAddress(OWNER_ADDRESS).endCell() },
        { type: 'cell', cell: Cell.EMPTY },
      ],
    });

    const data = await new DnsItem(ITEM_ADDRESS).getNftData(provider);

    expect(data.isInitialized).toBe(true);
    expect(data.index).toBe(42n);
    expect(data.collectionAddress?.equals(COLLECTION_ADDRESS)).toBe(true);
    expect(data.owner?.equals(OWNER_ADDRESS)).toBe(true);
  });

  it('handles a standalone item having no collection', async () => {
    const provider = mockProvider({
      get_nft_data: [
        { type: 'int', value: -1n },
        { type: 'int', value: 0n },
        { type: 'slice', cell: beginCell().storeUint(0, 2).endCell() },
        { type: 'slice', cell: beginCell().storeAddress(OWNER_ADDRESS).endCell() },
        { type: 'cell', cell: Cell.EMPTY },
      ],
    });

    const data = await new DnsItem(ITEM_ADDRESS).getNftData(provider);

    expect(data.collectionAddress).toBeNull();
  });
});

describe('getTelemintDomain', () => {
  it('assembles the domain from the reversed zero-separated parts', async () => {
    const provider = mockProvider({
      get_full_domain: [{ type: 'slice', cell: beginCell().storeStringTail('me\0t\0alice\0').endCell() }],
    });

    expect(await new DnsItem(ITEM_ADDRESS).getTelemintDomain(provider)).toBe('alice.t.me');
  });
});

function mockProvider(stackByMethod: Record<string, TupleItem[]>) {
  return {
    get(method: string) {
      if (!(method in stackByMethod)) {
        throw new Error(`Unknown get method "${method}"`);
      }

      return Promise.resolve({ stack: new TupleReader(stackByMethod[method]) });
    },
  } as unknown as ContractProvider;
}
