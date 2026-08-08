import type { StorageKey } from '../../../storages/types';

import { createTaskQueue } from '../../../../util/schedulers';
import { storage } from '../../../storages';

const writeQueues = new Map<StorageKey, ReturnType<typeof createTaskQueue>>();

function getWriteQueue(key: StorageKey) {
  let queue = writeQueues.get(key);
  if (!queue) {
    queue = createTaskQueue(1);
    writeQueues.set(key, queue);
  }
  return queue;
}

/**
 * Serializes SDK reconciler read-modify-write storage updates per key. Most storage drivers rely on the shared
 * `mutateItem` fallback (`getItem` + `setItem`), so concurrent intent/trace persistence must be queued to avoid
 * last-writer-wins losses of submitted hashes or durable TON aggregate projections.
 */
export function mutateReconcilerStorageItem<T>(
  key: StorageKey,
  mutate: (currentValue: T | undefined) => T | undefined,
) {
  return getWriteQueue(key).run(() => storage.mutateItem!(key, mutate));
}
