import { areSortedArraysEqual, mergeSortedArrays, shuffle, swapKeysAndValues } from './iteratees';

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
      arrays: [[1, 3, 5], [2, 4, 6]],
      expected: [1, 2, 3, 4, 5, 6],
    },
    {
      name: 'merges with duplicates when deduplicateEqual is false',
      arrays: [[1, 2, 3], [2, 3, 4]],
      expected: [1, 2, 2, 3, 3, 4],
    },
    {
      name: 'merges with deduplication when deduplicateEqual is true',
      arrays: [[1, 2, 3], [2, 3, 4]],
      deduplicateEqual: true,
      expected: [1, 2, 3, 4],
    },
    {
      name: 'returns the other array if one is empty',
      arrays: [[], [1, 2]],
      expected: [1, 2],
    },
    {
      name: 'returns the other array if one is empty (reverse)',
      arrays: [[1, 2], []],
      expected: [1, 2],
    },
    {
      name: 'copies the only input array instead of returning',
      arrays: [[1, 2]],
      expected: [1, 2],
    },
    {
      name: 'returns an empty array if `arrays` is empty',
      arrays: [],
      expected: [],
    },
    {
      name: 'respects custom compareFn (reverse order)',
      arrays: [['c', 'b', 'a'], ['d', 'b', 'a']],
      compareFn: stringDesc,
      expected: ['d', 'c', 'b', 'b', 'a', 'a'],
    },
    {
      name: 'does not lose items if the input arrays are not sorted',
      arrays: [[3, 5, 2], [4, 1, 6]],
      expected: [3, 4, 1, 5, 2, 6],
    },
    {
      name: 'merges multiple arrays',
      arrays: [[2, 7, 15], [4, 10, 19], [1, 8, 21], [3, 12, 16], [5, 11, 17], [6, 13, 20], [9, 14, 18]],
      expected: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
    },
  ])('$name', ({ arrays, compareFn = numberAsc, deduplicateEqual, expected }) => {
    const frozenArrays = Object.freeze(arrays.map((array) => Object.freeze(array)));
    const actualResult = mergeSortedArrays<any>(frozenArrays, compareFn, deduplicateEqual);
    expect(actualResult).toEqual(expected);
    expect(frozenArrays).not.toContain(actualResult);
  });
});

describe('shuffle', () => {
  it('should return an array with the same length', () => {
    const array = [1, 2, 3, 4, 5];
    const shuffled = shuffle([...array]);
    expect(shuffled.length).toBe(array.length);
  });

  it('should return an array with the same elements', () => {
    const array = [1, 2, 3, 4, 5];
    const shuffled = shuffle([...array]);
    expect(shuffled.sort()).toEqual(array.sort());
  });

  it('should return an array with a different order for a large enough array', () => {
    const array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const shuffled = shuffle([...array]);

    // This test has a small chance of failing if the shuffled array is the same as the original
    // but for an array of 10 elements, the probability is 1/10! which is very low.
    // So we check that the shuffled array is not the same as the original and shuffle it again.
    if (areSortedArraysEqual(array, shuffled)) {
      const shuffled2 = shuffle([...array]);

      expect(shuffled2).not.toEqual(shuffled);
    } else {
      expect(shuffled).not.toEqual(array);
    }
  });

  it('should handle an empty array', () => {
    const array: any[] = [];
    const shuffled = shuffle([...array]);
    expect(shuffled).toEqual([]);
  });

  it('should handle an array with one element', () => {
    const array = [1];
    const shuffled = shuffle([...array]);
    expect(shuffled).toEqual([1]);
  });
});
