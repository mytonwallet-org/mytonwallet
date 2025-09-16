import { bigintRandom, bigintReviver } from '../../../../util/bigint';

export function cloneDeep<T>(value: T): T {
  return JSON.parse(JSON.stringify(value), bigintReviver);
}

export function generateQueryId() {
  return 0;
}
