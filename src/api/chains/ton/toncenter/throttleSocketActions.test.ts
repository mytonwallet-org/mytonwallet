import type { ActivitiesUpdate } from '../../../common/websocket/abstractWsClient';
import type { SocketFinality } from './types';

import { pause } from '../../../../util/schedulers';
import { makeMockTransactionActivity } from '../../../../../tests/mocks';
import { throttleToncenterSocketActions } from './throttleSocketActions';

describe('throttleToncenterSocketActions', () => {
  const DELAY_MS = 20;

  it.concurrent('handles "pending -> long delay -> pending -> finalized" sequence correctly', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const firstPending = createMockUpdate('hash1', 'pending');
    const secondPending = createMockUpdate('hash1', 'pending');
    const finalized = createMockUpdate('hash1', 'finalized');

    // Step 1: First pending update arrives (should be immediate)
    throttled(firstPending);
    expect(onUpdates).toHaveBeenCalledWith([firstPending]);

    // Step 2: Wait longer than delayMs (simulating "long time")
    await pause(DELAY_MS + 10);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 3: Second pending update arrives (should be delayed because it's not the first)
    throttled(secondPending);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 4: Finalized update arrives immediately after (should be immediate and cancel any throttling)
    throttled(finalized);
    expect(onUpdates).toHaveBeenCalledTimes(2);
    expect(onUpdates).toHaveBeenNthCalledWith(2, [finalized]);

    // Step 5: Verify no additional calls after full delay
    await pause(DELAY_MS + 10);
    expect(onUpdates).toHaveBeenCalledTimes(2);
  });

  it.concurrent('throttles subsequent pending updates with same hash', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const firstPending = createMockUpdate('hash1', 'pending');
    const secondPending = createMockUpdate('hash1', 'pending');
    const thirdPending = createMockUpdate('hash1', 'pending');

    // First update should be immediate
    throttled(firstPending);
    expect(onUpdates).toHaveBeenCalledWith([firstPending]);

    // Subsequent updates should be throttled
    throttled(secondPending);
    throttled(thirdPending);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // After delay, only the latest update should be delivered
    await pause(DELAY_MS + 10); // Add small buffer for timing
    expect(onUpdates).toHaveBeenCalledTimes(2);
    expect(onUpdates).toHaveBeenNthCalledWith(2, [thirdPending]);
  });

  it.concurrent('handles multiple hashes independently', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const pending1 = createMockUpdate('hash1', 'pending');
    const pending2 = createMockUpdate('hash2', 'pending');
    const pending1Again = createMockUpdate('hash1', 'pending');

    // First updates for each hash should be immediate
    throttled(pending1);
    throttled(pending2);
    expect(onUpdates).toHaveBeenCalledTimes(2);

    // Subsequent update for hash1 should be throttled
    throttled(pending1Again);
    expect(onUpdates).toHaveBeenCalledTimes(2);

    // After delay, the throttled update should be delivered
    await pause(DELAY_MS + 10); // Add small buffer for timing
    expect(onUpdates).toHaveBeenCalledTimes(3);
    expect(onUpdates).toHaveBeenNthCalledWith(3, [pending1Again]);
  });

  it.concurrent('handles confirmed status updates correctly (not final, can be invalidated)', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const pending = createMockUpdate('hash1', 'pending');
    const confirmed = createMockUpdate('hash1', 'confirmed');
    const invalidation = createMockUpdate('hash1', 'finalized');
    invalidation.activities = []; // Empty activities = invalidation

    // Step 1: First pending update arrives (immediate)
    throttled(pending);
    expect(onUpdates).toHaveBeenCalledWith([pending]);

    // Step 2: Confirmed update arrives (should be throttled, not final)
    throttled(confirmed);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 3: Invalidation arrives (immediate, final)
    throttled(invalidation);
    expect(onUpdates).toHaveBeenCalledTimes(2);
    expect(onUpdates).toHaveBeenNthCalledWith(2, [invalidation]);

    // Step 4: Verify no additional calls after delay
    await pause(DELAY_MS + 10);
    expect(onUpdates).toHaveBeenCalledTimes(2);
  });

  it.concurrent('prevents finality regression: pending update cannot overwrite confirmed update', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const firstPending = createMockUpdate('hash1', 'pending');
    const confirmed = createMockUpdate('hash1', 'confirmed');
    const latePending = createMockUpdate('hash1', 'pending');

    // Step 1: First pending update arrives (immediate)
    throttled(firstPending);
    expect(onUpdates).toHaveBeenCalledWith([firstPending]);

    // Step 2: Confirmed update arrives (throttled)
    throttled(confirmed);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 3: A stale pending update arrives due to race condition (should be ignored)
    throttled(latePending);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 4: After delay, the confirmed update should be delivered, not the pending one
    await pause(DELAY_MS + 10);
    expect(onUpdates).toHaveBeenCalledTimes(2);
    expect(onUpdates).toHaveBeenNthCalledWith(2, [confirmed]);
  });

  it.concurrent('allows finality progression: confirmed can overwrite pending', async () => {
    const onUpdates = jest.fn();
    const throttled = throttleToncenterSocketActions(DELAY_MS, onUpdates);

    const firstPending = createMockUpdate('hash1', 'pending');
    const secondPending = createMockUpdate('hash1', 'pending');
    const confirmed = createMockUpdate('hash1', 'confirmed');

    // Step 1: First pending update arrives (immediate)
    throttled(firstPending);
    expect(onUpdates).toHaveBeenCalledWith([firstPending]);

    // Step 2: Another pending update arrives (throttled)
    throttled(secondPending);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 3: Confirmed update arrives (should overwrite pending)
    throttled(confirmed);
    expect(onUpdates).toHaveBeenCalledTimes(1);

    // Step 4: After delay, the confirmed update should be delivered
    await pause(DELAY_MS + 10);
    expect(onUpdates).toHaveBeenCalledTimes(2);
    expect(onUpdates).toHaveBeenNthCalledWith(2, [confirmed]);
  });
});

function createMockUpdate(
  messageHashNormalized: string,
  finality: SocketFinality,
): ActivitiesUpdate {
  return {
    address: 'test-address',
    messageHashNormalized,
    finality,
    activities: [makeMockTransactionActivity({ id: 'test-activity' })],
  };
}
