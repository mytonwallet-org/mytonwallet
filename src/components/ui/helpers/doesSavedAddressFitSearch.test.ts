import { doesSavedAddressFitSearch } from './doesSavedAddressFitSearch';

const ITEM = { address: 'UQAGRPabcdefKi0EA9', name: 'Fees · Near (Old)', domain: 'fees.ton' };

describe('doesSavedAddressFitSearch', () => {
  test('matches any part of address, name and domain case-insensitively', () => {
    expect(doesSavedAddressFitSearch(ITEM, 'uqagrp')).toBe(true);
    expect(doesSavedAddressFitSearch(ITEM, 'ABCDEF')).toBe(true);
    expect(doesSavedAddressFitSearch(ITEM, 'Old')).toBe(true);
    expect(doesSavedAddressFitSearch(ITEM, 'fees · n')).toBe(true);
    expect(doesSavedAddressFitSearch(ITEM, 's.TON')).toBe(true);
  });

  test('rejects missing text', () => {
    expect(doesSavedAddressFitSearch(ITEM, 'swaps')).toBe(false);
    expect(doesSavedAddressFitSearch({ address: 'UQA', name: 'Main' }, 'ton')).toBe(false);
  });
});
