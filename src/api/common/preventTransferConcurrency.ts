import type { ApiNetwork } from '../types';

import Deferred from '../../util/Deferred';
import { handleError } from '../../util/handleError';
import { createTaskQueue } from '../../util/schedulers';

type Task<T> = (finalizeInBackground: FinalizeInBackground) => MaybePromise<T>;

type FinalizeInBackground = (backgroundTask: () => Promise<void>) => void;

const queues: Record<string, ReturnType<typeof createTaskQueue>> = {};

/**
 * Prevents concurrency when sending multiple transfers. Preventing concurrency is necessary in TON, because every
 * transaction must have a unique sequential `seqno` that matched the one in the wallet data exactly.
 *
 * `task` is the function performing actions that should not run concurrently. It runs in 3 stages:
 *  - foreground — ends when `task` returns. The promise returned by `withoutTransferConcurrency` is settled the
 *    same moment with the same result;
 *  - background — ends when all the tasks, provided to the `finalizeInBackground` callback, finish.
 *
 * Before `task` is executed, the function waits for both stages of all the previous tasks for the same `network` and
 * `fromAddress` to complete.
 */
export function withoutTransferConcurrency<T>(network: ApiNetwork, fromAddress: string, task: Task<T>): Promise<T> {
  const queueKey = `${network} ${fromAddress}`;
  const foregroundDeferred = new Deferred<T>();
  const backgroundPromises: Promise<void>[] = [];

  const finalizeInBackground: FinalizeInBackground = (backgroundTask) => {
    backgroundPromises.push(backgroundTask().catch(handleError));
  };

  queues[queueKey] ??= createTaskQueue(1);

  void queues[queueKey].run(async () => {
    try {
      foregroundDeferred.resolve(await task(finalizeInBackground));
    } catch (err) {
      foregroundDeferred.reject(err);
    }

    await Promise.all(backgroundPromises);
  });

  return foregroundDeferred.promise;
}
