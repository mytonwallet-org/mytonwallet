import { resumeCurrentAccountPollingAfterWorkerStart } from './polling';

jest.mock('./polling', () => ({
  resumeCurrentAccountPollingAfterWorkerStart: jest.fn(),
  setActivePollingAccount: jest.fn(),
}));
jest.mock('../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../hooks', () => ({ callHook: jest.fn() }));

it('resolves login only after a successful valid-account resume', async () => {
  const { resumeCurrentAccountAfterWorkerStart } = await import('./accounts');
  const { waitLogin } = await import('../common/accounts');

  jest.mocked(resumeCurrentAccountPollingAfterWorkerStart).mockResolvedValueOnce(false);
  await expect(resumeCurrentAccountAfterWorkerStart()).rejects.toThrow('superseded');
  await expect(promiseState(waitLogin())).resolves.toBe('pending');

  jest.mocked(resumeCurrentAccountPollingAfterWorkerStart).mockResolvedValueOnce(undefined);
  await expect(resumeCurrentAccountAfterWorkerStart()).resolves.toBeUndefined();
  await expect(promiseState(waitLogin())).resolves.toBe('pending');

  jest.mocked(resumeCurrentAccountPollingAfterWorkerStart).mockResolvedValueOnce(true);
  await expect(resumeCurrentAccountAfterWorkerStart()).resolves.toBeUndefined();
  await expect(promiseState(waitLogin())).resolves.toBe('settled');
});

async function promiseState(promise: Promise<unknown>) {
  return Promise.race([
    promise.then(() => 'settled'),
    new Promise<string>((resolve) => setTimeout(() => resolve('pending'), 10)),
  ]);
}
