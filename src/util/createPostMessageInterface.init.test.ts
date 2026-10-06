import { createPostMessageInterface } from './createPostMessageInterface';
import generateUniqueId from './generateUniqueId';

import { createConnector } from './PostMessageConnector';

jest.mock('./logs', () => ({ logDebugError: jest.fn() }));
jest.mock('./generateUniqueId', () => ({ __esModule: true, default: jest.fn() }));

const mockedGenerateUniqueId = jest.mocked(generateUniqueId);
const cleanups: NoneToVoidFunction[] = [];

function connect(api: Record<string, AnyFunction> | AnyFunction) {
  let receiveRequest: (event: MessageEvent) => void;
  let receiveResponse: (event: MessageEvent) => void;
  const responses: any[] = [];
  const client = {
    postMessage: (data: any) => receiveRequest({ data } as MessageEvent),
    addEventListener: (_: string, handler: typeof receiveResponse) => { receiveResponse = handler; },
    removeEventListener: jest.fn(),
  } as unknown as Worker;
  const server = {
    postMessage: (data: any) => {
      responses.push(data);
      receiveResponse({ data } as MessageEvent);
    },
    addEventListener: (_: string, handler: typeof receiveRequest) => { receiveRequest = handler; },
    removeEventListener: jest.fn(),
  } as unknown as Worker;
  cleanups.push(createPostMessageInterface(api, undefined, server));
  const connector = createConnector(client);
  cleanups.push(() => connector.destroy());
  return { connector, responses };
}

async function settle(promise: Promise<void>) {
  return Promise.race([
    promise.then(() => 'resolved', (error: Error) => error),
    new Promise<string>((resolve) => { setTimeout(() => resolve('pending'), 30); }),
  ]);
}

afterEach(() => {
  cleanups.splice(0).forEach((cleanup) => cleanup());
  jest.clearAllMocks();
});

it.each(['sync', 'async'] as const)('correlates a %s init error once and permits an explicit retry', async (mode) => {
  const error = Object.assign(new Error('migration failed'), { code: 'MIGRATION_FAILED' });
  const init = jest.fn();
  if (mode === 'sync') {
    init.mockImplementationOnce(() => {
      throw error;
    });
  } else {
    init.mockRejectedValueOnce(error);
  }
  init.mockResolvedValueOnce(undefined);
  const api = mode === 'sync' ? init : { init };
  const { connector, responses } = connect(api);
  mockedGenerateUniqueId.mockReturnValueOnce('failed-init').mockReturnValueOnce('retry-init');

  const result = await settle(connector.init({ storage: 'chrome' }));

  expect(result).toBeInstanceOf(Error);
  expect(result).toMatchObject({ message: error.message, code: error.code });
  expect(responses).toEqual([{
    type: 'methodResponse',
    channel: undefined,
    messageId: 'failed-init',
    error: expect.objectContaining({ message: error.message, code: error.code }),
  }]);

  await expect(connector.init()).resolves.toBeUndefined();
  expect(responses).toHaveLength(2);
  expect(responses[1]).toEqual({
    type: 'methodResponse', channel: undefined, messageId: 'retry-init', response: undefined,
  });
  expect(init).toHaveBeenCalledTimes(2);
});

it.each(['', 0])('does not treat messageId %j as notification-only init', async (messageId) => {
  mockedGenerateUniqueId.mockReturnValueOnce(messageId as string);
  const { connector, responses } = connect({ init: () => Promise.reject(new Error('failed')) });

  expect(await settle(connector.init())).toBeInstanceOf(Error);
  expect(responses).toHaveLength(1);
  expect(responses[0]).toMatchObject({ type: 'methodResponse', messageId, error: { message: 'failed' } });
});
