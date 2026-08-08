import { createTaskQueue } from '../../util/schedulers';

const queues = new Map<string, ReturnType<typeof createTaskQueue>>();

/** Keeps SDK reconciliation snapshots and their store patches ordered per account. */
export function runActivityUpdateInOrder<T>(accountId: string, task: () => Promise<T>) {
  let queue = queues.get(accountId);
  if (!queue) {
    queue = createTaskQueue(1);
    queues.set(accountId, queue);
  }

  return queue.run(task);
}
