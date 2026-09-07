import type { ApiActivity } from '../../types';
import type { ActivityStream, OnActivityUpdate } from './toncenter';

import { makeMockTransactionActivity } from '../../../../tests/mocks';
import { fetchStoredWallet } from '../../common/accounts';
import { swapReplaceActivities } from '../../common/swap';
import { reloadIncompleteActivities } from './activities';
import { RichActivityStream } from './richActivityStream';

jest.mock('../../common/accounts', () => ({ fetchStoredWallet: jest.fn() }));
jest.mock('../../common/swap', () => ({ swapReplaceActivities: jest.fn() }));
jest.mock('./activities', () => ({ reloadIncompleteActivities: jest.fn() }));

const ACCOUNT_ID = '0-mainnet';
const TRACE_HASH = 'trace-hash-1';

function makeRawStream() {
  let push: OnActivityUpdate | undefined;
  const stream = {
    onUpdate: (callback: OnActivityUpdate) => {
      push = callback;
      return () => undefined;
    },
    onLoadingChange: () => () => undefined,
  } as unknown as ActivityStream;

  return { stream, push: (confirmed: ApiActivity[], pending: ApiActivity[]) => push!(confirmed, pending) };
}

function flushPromises() {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
}

describe('RichActivityStream', () => {
  let updates: { confirmed: ApiActivity[]; pending: readonly ApiActivity[] }[];

  beforeEach(() => {
    jest.clearAllMocks();
    updates = [];
    jest.mocked(fetchStoredWallet).mockResolvedValue({ address: 'UQAddress' } as any);
    jest.mocked(reloadIncompleteActivities).mockImplementation((_n, _a, activities) => Promise.resolve(activities));
    jest.mocked(swapReplaceActivities).mockImplementation((_id, activities) => Promise.resolve(activities));
  });

  /** Plays a trace through the raw stream: first its pending version, then the confirmed one */
  async function playTrace() {
    const raw = makeRawStream();
    const stream = new RichActivityStream(ACCOUNT_ID, raw.stream);
    stream.onUpdate((confirmed, pending) => {
      updates.push({ confirmed, pending });
    });

    const shared = { externalMsgHashNorm: TRACE_HASH, timestamp: 1_700_000_000_000 };
    const pending = makeMockTransactionActivity({ ...shared, id: `${TRACE_HASH}:100-0`, status: 'pending' });
    const confirmed = makeMockTransactionActivity({ ...shared, id: 'trace-id-1:100-0', status: 'completed' });

    raw.push([], [pending]);
    raw.push([confirmed], []);
    await flushPromises();

    return { stream, confirmed };
  }

  it('replaces the pending activity once the confirmed one is enriched', async () => {
    const { stream, confirmed } = await playTrace();

    expect(reloadIncompleteActivities).toHaveBeenCalled();
    expect(swapReplaceActivities).toHaveBeenCalled();
    expect(updates[updates.length - 1].pending).toEqual([]);
    expect(updates.flatMap((update) => update.confirmed)).toEqual([confirmed]);

    stream.destroy();
  });

  it('replaces the pending activity even when enrichment fails', async () => {
    // Enrichment starts by reading the stored wallet, so a rejection here fails the whole batch.
    jest.mocked(fetchStoredWallet).mockRejectedValue(new Error('storage is unavailable'));

    const { stream, confirmed } = await playTrace();

    // The batch is reported raw: nothing downstream of the failed step ran, so the rows carry no decoration.
    expect(reloadIncompleteActivities).not.toHaveBeenCalled();
    expect(swapReplaceActivities).not.toHaveBeenCalled();
    expect(updates[updates.length - 1].pending).toEqual([]);
    expect(updates.flatMap((update) => update.confirmed)).toEqual([confirmed]);

    stream.destroy();
  });
});
