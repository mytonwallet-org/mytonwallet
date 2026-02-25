import { pause } from '../../util/schedulers';

interface PaginatedOptions<T> {
  signal?: AbortSignal;
  batchLimit: number;
  pauseMs: number;
  fetchBatch: (cursor: number) => Promise<T[]>;
}

/**
 * Streaming paginated fetch. Fetches batches sequentially, delivering each
 * via `onBatch`, until a batch smaller than `batchLimit` is returned (indicating the last page).
 *
 * `cursor` is a 0-based page number passed to `fetchBatch`. Each chain maps it
 * to its own pagination scheme (e.g. TON: `offset = cursor * batchLimit`,
 * Solana: `page = cursor + 1`).
 *
 * Respects `signal` for cooperative cancellation - stops fetching when aborted.
 */
export async function streamPaginated<T>(
  options: PaginatedOptions<T> & { onBatch: (batch: T[]) => void },
): Promise<void> {
  const { signal, batchLimit, pauseMs, onBatch, fetchBatch } = options;
  let cursor = 0;

  while (true) {
    if (signal?.aborted) break;

    const batch = await fetchBatch(cursor);

    if (signal?.aborted) break;

    onBatch(batch);

    if (batch.length < batchLimit) break;

    cursor += 1;
    await pause(pauseMs);
  }
}

/** Convenience wrapper: fetches all pages and returns the accumulated result. */
export async function fetchAllPaginated<T>(options: PaginatedOptions<T>): Promise<T[]> {
  const all: T[] = [];
  await streamPaginated({ ...options, onBatch: (batch) => all.push(...batch) });
  return all;
}
