import { callApi, callApiWithThrow, initApi } from './connector';

const mockInit = jest.fn();
const mockRequest = jest.fn();

jest.mock('../../../util/PostMessageConnector', () => ({
  createExtensionConnector: () => ({ init: mockInit, request: mockRequest }),
}));
jest.mock('../../../util/windowProvider', () => ({ createWindowProviderForExtension: jest.fn() }));
jest.mock('../../../util/chunkLoading', () => ({ reportApiChunkLoadError: jest.fn() }));
jest.mock('../../../util/logs', () => ({ logDebugError: jest.fn(), logDebugApi: jest.fn() }));

const originalExtension = process.env.IS_EXTENSION;

beforeAll(() => {
  process.env.IS_EXTENSION = '1';
});
afterAll(() => {
  if (originalExtension === undefined) delete process.env.IS_EXTENSION;
  else process.env.IS_EXTENSION = originalExtension;
});
beforeEach(() => {
  mockInit.mockReset();
  mockRequest.mockReset();
});

it('returns undefined from tolerant calls when init fails without dispatching the method', async () => {
  mockInit.mockRejectedValueOnce(new Error('migration failed'));
  initApi(jest.fn(), {});

  await expect(callApi('ping')).resolves.toBeUndefined();
  expect(mockRequest).not.toHaveBeenCalled();
});

it('rejects strict calls with the init error without dispatching the method', async () => {
  const error = new Error('migration failed');
  mockInit.mockRejectedValueOnce(error);
  initApi(jest.fn(), {});

  await expect(callApiWithThrow('ping')).rejects.toBe(error);
  expect(mockRequest).not.toHaveBeenCalled();
});

it('dispatches after a successful explicit retry of failed initialization', async () => {
  mockInit.mockRejectedValueOnce(new Error('migration failed'));
  initApi(jest.fn(), {});
  await expect(callApiWithThrow('ping')).rejects.toThrow('migration failed');

  mockInit.mockResolvedValueOnce(undefined);
  mockRequest.mockResolvedValueOnce('pong');
  initApi(jest.fn(), {});

  await expect(callApi('ping')).resolves.toBe('pong');
  expect(mockRequest).toHaveBeenCalledTimes(1);
  expect(mockRequest).toHaveBeenCalledWith({ name: 'ping', args: [] });
});
