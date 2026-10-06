import { MessageChannel } from 'node:worker_threads';

import { getExtensionWindowIds, initExtensionWindow } from './extensionWindow';

describe('extension window identity', () => {
  const addEventListener = jest.fn();
  const getCurrent = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    Object.assign(self, { MessageChannel });
    Object.defineProperty(self, 'chrome', {
      configurable: true,
      value: {
        runtime: { getURL: (path: string) => `chrome-extension://wallet/${path}` },
        windows: { getCurrent },
      },
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: { addEventListener },
    });
  });

  it('returns the browser window identity through a real MessageChannel', async () => {
    getCurrent.mockImplementation((callback) => callback({ id: 41, type: 'popup' }));
    initExtensionWindow();
    const listener = addEventListener.mock.calls[0][1];
    Object.assign(self, {
      clients: {
        matchAll: () => Promise.resolve([{
          url: 'chrome-extension://wallet/index.html',
          frameType: 'top-level',
          postMessage: (data: unknown, ports: MessagePort[]) => listener({ data, ports }),
        }]),
      },
    });

    await expect(getExtensionWindowIds()).resolves.toEqual({ windowIds: [41], isComplete: true });
  });

  it('can initialize a Firefox extension page with no service worker container', () => {
    Reflect.deleteProperty(navigator, 'serviceWorker');

    expect(initExtensionWindow).not.toThrow();
  });
});
