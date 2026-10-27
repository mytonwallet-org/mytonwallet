import type { DefaultWatchedWallet, InMessageCallback } from './abstractWsClient';

import { logDebugError } from '../../../util/logs';
import ReconnectingWebSocket from '../../../util/reconnectingWebsocket';
import { AbstractWebsocketClient } from './abstractWsClient';

jest.mock('../../../util/logs', () => ({
  ...jest.requireActual('../../../util/logs'),
  logDebugError: jest.fn(),
}));

jest.mock('../../../util/reconnectingWebsocket', () => {
  class MockSocket {
    static instances: MockSocket[] = [];

    isConnected = true;

    send = jest.fn();

    close = jest.fn();

    #messageListeners: ((message: unknown) => void)[] = [];

    constructor() {
      MockSocket.instances.push(this);
    }

    onMessage(callback: (message: unknown) => void) {
      this.#messageListeners.push(callback);
      return () => undefined;
    }

    onConnect() {
      return () => undefined;
    }

    onDisconnect() {
      return () => undefined;
    }

    receive(message: unknown) {
      this.#messageListeners.forEach((callback) => callback(message));
    }
  }

  return { __esModule: true, default: MockSocket };
});

type MockSocket = { receive(message: unknown): void };

class TestClient extends AbstractWebsocketClient<unknown, unknown, DefaultWatchedWallet, never, never> {
  handler = jest.fn<ReturnType<InMessageCallback<unknown>>, [unknown]>();

  protected handleSocketMessage: InMessageCallback<unknown> = (message) => this.handler(message);

  protected handleSocketConnect = () => undefined;

  protected handleSocketDisconnect = () => undefined;

  protected sendWatchedWalletsToSocket = () => undefined;
}

async function connectClient() {
  const client = new TestClient(new URL('wss://example.com'));
  client.watchWallets([{ address: 'address', chain: 'ton' }]);
  await jest.advanceTimersByTimeAsync(1000);

  const { instances } = ReconnectingWebSocket as unknown as { instances: MockSocket[] };

  return { client, socket: instances[instances.length - 1] };
}

describe('AbstractWebsocketClient', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.mocked(logDebugError).mockClear();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('logs a rejection of an async message handler', async () => {
    const { client, socket } = await connectClient();
    const error = new Error('Balance fetch failed');
    client.handler.mockImplementation(() => Promise.reject(error));

    socket.receive({});
    await jest.advanceTimersByTimeAsync(0);

    expect(logDebugError).toHaveBeenCalledWith(expect.any(String), error);
  });

  it('lets a synchronous message handler error propagate', async () => {
    const { client, socket } = await connectClient();
    const error = new Error('Malformed message');
    client.handler.mockImplementation(() => {
      throw error;
    });

    expect(() => socket.receive({})).toThrow(error);
  });
});
