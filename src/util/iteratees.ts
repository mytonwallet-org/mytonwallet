type CollectionByKey<Member> = Record<number | string, Member>;
type GroupedByKey<Member> = Record<number | string, Member[]>;

type OrderDirection =
  'asc'
  | 'desc';

type OrderCallback<T> = (member: T) => unknown;

export function buildCollectionByKey<T extends AnyLiteral>(collection: readonly T[], key: keyof T): CollectionByKey<T> {
  return collection.reduce((byKey: CollectionByKey<T>, member: T) => {
    byKey[member[key]] = member;

    return byKey;
  }, {});
}

export function buildArrayCollectionByKey<T extends AnyLiteral>(collection: T[], key: keyof T) {
  return collection.reduce((byKey: CollectionByKey<Array<T>>, member: T) => {
    const collectionKey = member[key];
    if (!byKey[collectionKey]) {
      byKey[collectionKey] = [];
    }
    byKey[collectionKey].push(member);

    return byKey;
  }, {});
}

export function groupBy<T extends AnyLiteral>(collection: readonly T[], key: keyof T): GroupedByKey<T> {
  return collection.reduce((byKey: GroupedByKey<T>, member: T) => {
    const groupKey = member[key];

    if (!byKey[groupKey]) {
      byKey[groupKey] = [member];
    } else {
      byKey[groupKey].push(member);
    }

    return byKey;
  }, {});
}

export function mapValues<R, M>(
  byKey: CollectionByKey<M>,
  callback: (member: M, key: string, index: number, originalByKey: CollectionByKey<M>) => R,
): CollectionByKey<R> {
  return Object.keys(byKey).reduce((newByKey: CollectionByKey<R>, key, index) => {
    newByKey[key] = callback(byKey[key], key, index, byKey);
    return newByKey;
  }, {});
}

export function pick<T, K extends keyof T>(object: T, keys: K[]) {
  return keys.reduce((result, key) => {
    result[key] = object[key];
    return result;
  }, {} as Pick<T, K>);
}

export function pickTruthy<T, K extends keyof T>(object: T, keys: K[]) {
  return keys.reduce((result, key) => {
    if (object[key]) {
      result[key] = object[key];
    }

    return result;
  }, {} as Pick<T, K>);
}

export function omit<T extends object, K extends keyof T>(object: T, keys: K[]): Omit<T, K> {
  const stringKeys = new Set(keys.map(String));
  const savedKeys = Object.keys(object)
    .filter((key) => !stringKeys.has(key)) as Array<Exclude<keyof T, K>>;

  return pick(object, savedKeys);
}

export function omitUndefined<T extends object>(object: T): T {
  return Object.keys(object).reduce((result, stringKey) => {
    const key = stringKey as keyof T;
    if (object[key] !== undefined) {
      result[key] = object[key];
    }
    return result;
  }, {} as T);
}

export function orderBy<T>(
  collection: T[],
  orderRule: (keyof T) | OrderCallback<T> | ((keyof T) | OrderCallback<T>)[],
  mode: OrderDirection | [OrderDirection, OrderDirection] = 'asc',
): T[] {
  function compareValues(a: T, b: T, currentOrderRule: (keyof T) | OrderCallback<T>, isAsc: boolean) {
    const aValue = (typeof currentOrderRule === 'function' ? currentOrderRule(a) : a[currentOrderRule]) || 0;
    const bValue = (typeof currentOrderRule === 'function' ? currentOrderRule(b) : b[currentOrderRule]) || 0;

    if (aValue === bValue) return 0;

    const condition = isAsc ? aValue > bValue : aValue < bValue;
    return condition ? 1 : -1;
  }

  if (Array.isArray(orderRule)) {
    const [mode1, mode2] = Array.isArray(mode) ? mode : [mode, mode];
    const [orderRule1, orderRule2] = orderRule;
    const isAsc1 = mode1 === 'asc';
    const isAsc2 = mode2 === 'asc';

    return collection.sort((a, b) => {
      return compareValues(a, b, orderRule1, isAsc1) || compareValues(a, b, orderRule2, isAsc2);
    });
  }

  const isAsc = mode === 'asc';
  return collection.sort((a, b) => {
    return compareValues(a, b, orderRule, isAsc);
  });
}

export function unique<T>(array: readonly T[]): T[] {
  return Array.from(new Set(array));
}

export function compact<T>(array: T[]) {
  return array.filter(Boolean);
}

export function areSortedArraysEqual<T>(array1: readonly T[], array2: readonly T[]) {
  if (array1.length !== array2.length) {
    return false;
  }

  return array1.every((item, i) => item === array2[i]);
}

export function split<T>(array: T[], chunkSize: number) {
  const result: T[][] = [];
  for (let i = 0; i < array.length; i += chunkSize) {
    result.push(array.slice(i, i + chunkSize));
  }

  return result;
}

export function cloneDeep<T>(value: T): T {
  if (!isObject(value)) {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(cloneDeep) as typeof value;
  }

  return Object.keys(value).reduce((acc, key) => {
    acc[key as keyof T] = cloneDeep(value[key as keyof T]);
    return acc;
  }, {} as T);
}

export function isLiteralObject(value: any): value is AnyLiteral {
  return isObject(value) && !Array.isArray(value);
}

function isObject(value: any): value is object {
  // eslint-disable-next-line no-null/no-null
  return typeof value === 'object' && value !== null;
}

export function findLast<T>(array: Array<T>, predicate: (value: T, index: number, obj: T[]) => boolean): T | undefined {
  let cursor = array.length;

  while (cursor--) {
    if (predicate(array[cursor], cursor, array)) {
      return array[cursor];
    }
  }

  return undefined;
}

export function range(start: number, end: number) {
  const arr: number[] = [];
  for (let i = start; i < end;) {
    arr.push(i++);
  }
  return arr;
}

export function fromKeyValueArrays<T>(keys: string[], values: T[] | T) {
  return keys.reduce((acc, key, index) => {
    acc[key] = Array.isArray(values) ? values[index] : values;
    return acc;
  }, {} as Record<string, T>);
}

export function extractKey<T, K extends keyof T>(array: readonly T[], key: K): T[K][] {
  return array.map((value) => value[key]);
}

export function findDifference<T>(array1: Iterable<T>, array2: Iterable<T>): T[] {
  const set2 = new Set(array2);
  const diff: T[] = [];

  for (const element of array1) {
    if (!set2.has(element)) {
      diff.push(element);
    }
  }

  return diff;
}

export function filterValues<M>(
  byKey: CollectionByKey<M>,
  callback: (member: M, key: string, index: number, originalByKey: CollectionByKey<M>) => boolean,
): CollectionByKey<M> {
  return Object.keys(byKey).reduce((newByKey: CollectionByKey<M>, key, index) => {
    if (callback(byKey[key], key, index, byKey)) {
      newByKey[key] = byKey[key];
    }

    return newByKey;
  }, {});
}

export function uniqueByKey<T>(array: readonly T[], key: keyof T, shouldKeepFirst?: boolean) {
  if (shouldKeepFirst) {
    array = [...array].reverse();
  }

  const result = [...new Map(array.map((item) => [item[key], item])).values()];

  if (shouldKeepFirst) {
    result.reverse();
  }

  return result;
}

export function intersection<T>(x: Set<T>, y: Set<T>): Set<T> {
  const result = new Set<T>();
  for (const elem of y) {
    if (x.has(elem)) {
      result.add(elem);
    }
  }
  return result;
}

export function swapKeysAndValues<
  K extends string | number,
  V extends keyof any,
>(object: Record<K, V>): Record<V, `${K}`> {
  const result = {} as any;
  for (const [key, value] of Object.entries(object)) {
    result[value as any] = key;
  }
  return result;
}

/**
 * The arrays inside `arrays` must be sorted according to `compareFn`, otherwise the result is not guaranteed.
 * `deduplicateEqual` doesn't remove duplicates if the individual input arrays contain duplicates.
 * Always returns a new array (not any of the input arrays).
 */
export function mergeSortedArrays<T>(
  arrays: readonly (readonly T[])[],
  compareFn: (item1: T, item2: T) => number,
  deduplicateEqual?: boolean,
): T[] {
  // This is a divide-and-conquer algorithm combined with a 2-pointers algorithm. Its time complexity is O(n*log(n)*m),
  // where n is the number of arrays and m is the average array size. The heap algorithm is slightly faster, but it has
  // the same time complexity and its implementation in JS is too bulky.
  // This problem on LeetCode: https://leetcode.com/problems/merge-k-sorted-lists/

  if (arrays.length === 1) return [...arrays[0]];

  let toMerge = arrays as T[][];

  while (toMerge.length > 1) {
    const nextToMerge: T[][] = [];

    for (let i = 0; i < toMerge.length; i += 2) {
      nextToMerge.push(
        i + 1 < toMerge.length
          ? merge2(toMerge[i], toMerge[i + 1])
          : toMerge[i], // If toMerge.length is odd, the last iteration has only 1 subarray to merge
      );
    }

    toMerge = nextToMerge;
  }

  return toMerge[0] ?? [];

  function merge2(arr1: readonly T[], arr2: readonly T[]) {
    let index1 = 0;
    let index2 = 0;
    const result: T[] = [];

    while (index1 < arr1.length && index2 < arr2.length) {
      const compareResult = compareFn(arr1[index1], arr2[index2]);

      if (compareResult === 0) {
        result.push(arr1[index1]);
        if (!deduplicateEqual) {
          result.push(arr2[index2]);
        }
        index1++;
        index2++;
      } else if (compareResult < 0) {
        result.push(arr1[index1++]);
      } else {
        result.push(arr2[index2++]);
      }
    }

    result.push(...arr1.slice(index1));
    result.push(...arr2.slice(index2));

    return result;
  }
}

export function shuffle<T>(array: T[]): T[] {
  let currentIndex = array.length;
  let randomIndex;

  while (currentIndex !== 0) {
    randomIndex = Math.floor(Math.random() * currentIndex);
    currentIndex--;

    [array[currentIndex], array[randomIndex]] = [array[randomIndex], array[currentIndex]];
  }

  return array;
}

export function orderByPattern<T, K>(arr: T[], getValue: (item: T) => K, pattern: K[]) {
  const patternWeights = new Map(pattern.map((val, index) => [val, index]));

  return [...arr].sort((a, b) => {
    const valueA = getValue(a);
    const valueB = getValue(b);

    const indexA = patternWeights.has(valueA) ? patternWeights.get(valueA)! : Infinity;
    const indexB = patternWeights.has(valueB) ? patternWeights.get(valueB)! : Infinity;

    return indexA - indexB;
  });
};
