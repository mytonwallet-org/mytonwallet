import Deferred from '../../util/Deferred';
import generateUniqueId from '../../util/generateUniqueId';
import { pause } from '../../util/schedulers';
import { withoutTransferConcurrency } from './preventTransferConcurrency';

describe('withoutTransferConcurrency', () => {
  const network = 'mainnet';

  it.concurrent('resolves sequentially for same address', async () => {
    const task1Deferred = new Deferred<void>();
    const task1 = jest.fn().mockImplementation(async () => {
      await task1Deferred.promise;
      return 1;
    });
    const task2 = jest.fn().mockReturnValue(2);
    const address = generateUniqueId();

    const t1 = withoutTransferConcurrency(network, address, task1);
    const t2 = withoutTransferConcurrency(network, address, task2);

    expect(task1).toHaveBeenCalledTimes(1);
    await pause(1);
    expect(task2).not.toHaveBeenCalled();
    task1Deferred.resolve();
    await pause(1);
    await expect(t1).resolves.toBe(1);
    await pause(1);
    expect(task2).toHaveBeenCalledTimes(1);
    await expect(t2).resolves.toBe(2);
  });

  it.concurrent('waits for background task before starting the next task', async () => {
    const task1BgDeferred = new Deferred<void>();
    const task1 = jest.fn().mockImplementation((finalizeInBackground) => {
      finalizeInBackground(() => task1BgDeferred.promise);
      return 1;
    });
    const task2 = jest.fn().mockReturnValue(2);
    const address = generateUniqueId();

    const t1 = withoutTransferConcurrency(network, address, task1);
    const t2 = withoutTransferConcurrency(network, address, task2);

    await expect(t1).resolves.toBe(1);
    await pause(1);
    expect(task2).not.toHaveBeenCalled();
    task1BgDeferred.resolve();
    await pause(1);
    expect(task2).toHaveBeenCalledTimes(1);
    await expect(t2).resolves.toBe(2);
  });

  it.concurrent('propagates error from task', async () => {
    const error = new Error('fail');
    const address = generateUniqueId();

    const t1 = withoutTransferConcurrency(network, address, jest.fn().mockRejectedValue(error));
    const t2 = withoutTransferConcurrency(network, address, jest.fn().mockResolvedValue(2));

    await expect(t1).rejects.toBe(error);
    await expect(t2).resolves.toBe(2);
  });

  it.concurrent('does not block for different addresses', async () => {
    const task1 = jest.fn().mockImplementation(() => pause(10).then(() => 1));
    const task2 = jest.fn().mockImplementation(() => pause(10).then(() => 2));

    const t1 = withoutTransferConcurrency(network, generateUniqueId(), task1);
    const t2 = withoutTransferConcurrency(network, generateUniqueId(), task2);

    await pause(1);
    expect(task1).toHaveBeenCalledTimes(1);
    expect(task2).toHaveBeenCalledTimes(1);
    await expect(Promise.all([t1, t2])).resolves.toEqual([1, 2]);
  });
});
