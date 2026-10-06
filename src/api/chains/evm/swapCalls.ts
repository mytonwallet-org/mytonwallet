import type { ApiEvmSwapCall } from '../../types/backend';
import type { EvmMetaTransaction } from './smartAccount/types';

export function serializeEvmSwapCalls(calls: EvmMetaTransaction[]): ApiEvmSwapCall[] {
  return calls.map(({ to, value, data }) => ({
    to,
    value: value?.toString(),
    data: data ?? '0x',
  }));
}
