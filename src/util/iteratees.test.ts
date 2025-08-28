import { mergeSortedArrays, swapKeysAndValues } from './iteratees';

describe('swapKeysAndValues', () => {
  it.each([
    {
      name: 'mixed string and number keys/values',
      input: { foo: 123, bar: 456, 789: 'baz' },
      expected: { 123: 'foo', 456: 'bar', baz: '789' },
    },
    {
      name: 'empty object',
      input: {},
      expected: {},
    },
    {
      name: 'duplicate values by keeping the last key',
      input: { a: 'same', b: 'same', c: 'different' },
      expected: { same: 'b', different: 'c' },
    },
  ])('handles $name', ({ input, expected }) => {
    expect(swapKeysAndValues(input as any)).toEqual(expected);
  });
});

describe('mergeSortedArrays', () => {
  const numberAsc = (a: number, b: number) => a - b;
  const stringDesc = (a: string, b: string) => b.localeCompare(a);

  it.each([
    {
      name: 'merges two sorted arrays of numbers',
      arr1: [1, 3, 5],
      arr2: [2, 4, 6],
      compareFn: numberAsc,
      expected: [1, 2, 3, 4, 5, 6],
    },
    {
      name: 'merges with duplicates when deduplicateEqual is false',
      arr1: [1, 2, 3],
      arr2: [2, 3, 4],
      compareFn: numberAsc,
      expected: [1, 2, 2, 3, 3, 4],
    },
    {
      name: 'merges with deduplication when deduplicateEqual is true',
      arr1: [1, 2, 3],
      arr2: [2, 3, 4],
      compareFn: numberAsc,
      deduplicateEqual: true,
      expected: [1, 2, 3, 4],
    },
    {
      name: 'returns the other array if one is empty',
      arr1: [],
      arr2: [1, 2],
      compareFn: numberAsc,
      expected: [1, 2],
    },
    {
      name: 'returns the other array if one is empty (reverse)',
      arr1: [1, 2],
      arr2: [],
      compareFn: numberAsc,
      expected: [1, 2],
    },
    {
      name: 'respects custom compareFn (reverse order)',
      arr1: ['c', 'b', 'a'],
      arr2: ['d', 'b', 'a'],
      compareFn: stringDesc,
      expected: ['d', 'c', 'b', 'b', 'a', 'a'],
    },
    {
      name: 'does not lose items if the input arrays are not sorted',
      arr1: [3, 5, 2],
      arr2: [4, 1, 6],
      compareFn: numberAsc,
      expected: [3, 4, 1, 5, 2, 6],
    },
  ])('$name', ({ arr1, arr2, compareFn, deduplicateEqual, expected }) => {
    expect(mergeSortedArrays<any>(arr1, arr2, compareFn, deduplicateEqual)).toEqual(expected);
  });
});
