import { PAGE_CONNECTOR_CHANNEL } from './config';

type MessageListener = (event: MessageEvent) => void;

describe('pageContentProxy', () => {
  let addEventListenerSpy: jest.SpyInstance;
  let postMessage: jest.Mock;
  let listener: MessageListener;

  beforeEach(() => {
    jest.resetModules();

    postMessage = jest.fn();
    listener = undefined as unknown as MessageListener;

    addEventListenerSpy = jest.spyOn(window, 'addEventListener').mockImplementation((
      type: string,
      callback: EventListenerOrEventListenerObject,
    ) => {
      if (type === 'message') {
        listener = callback as MessageListener;
      }
    });

    Object.defineProperty(global, 'chrome', {
      configurable: true,
      value: {
        runtime: {
          connect: jest.fn(() => ({
            onMessage: {
              addListener: jest.fn(),
            },
            postMessage,
          })),
        },
      },
    });
  });

  afterEach(() => {
    addEventListenerSpy.mockRestore();
    // @ts-expect-error The test deletes its mocked extension runtime.
    delete global.chrome;
  });

  function initProxy() {
    jest.isolateModules(() => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      require('./pageContentProxy');
    });

    expect(listener).toEqual(expect.any(Function));
  }

  function emitMessage({
    channel = PAGE_CONNECTOR_CHANNEL,
    origin = window.location.origin,
    source = window,
  }: {
    channel?: string;
    origin?: string;
    source?: MessageEventSource | null;
  } = {}) {
    const payload = {
      channel,
      type: 'callMethod',
      name: 'processDeeplink',
      args: [{ url: 'ton://transfer/attacker' }],
      messageId: 'message-id',
    };

    listener(new MessageEvent('message', {
      data: payload,
      origin,
      source,
    }));

    return payload;
  }

  it('forwards same-window same-origin channel messages to the extension port', () => {
    initProxy();

    const payload = emitMessage();

    expect(postMessage).toHaveBeenCalledTimes(1);
    expect(postMessage).toHaveBeenCalledWith(payload);
  });

  it('ignores cross-origin iframe messages', () => {
    initProxy();

    const iframe = document.createElement('iframe');
    document.body.appendChild(iframe);

    emitMessage({
      origin: 'https://evil.example',
      source: iframe.contentWindow,
    });

    iframe.remove();

    expect(postMessage).not.toHaveBeenCalled();
  });

  it('ignores same-origin iframe messages', () => {
    initProxy();

    const iframe = document.createElement('iframe');
    document.body.appendChild(iframe);

    emitMessage({
      source: iframe.contentWindow,
    });

    iframe.remove();

    expect(postMessage).not.toHaveBeenCalled();
  });

  it('ignores same-window messages from a different origin', () => {
    initProxy();

    emitMessage({
      origin: 'https://evil.example',
    });

    expect(postMessage).not.toHaveBeenCalled();
  });

  it('ignores messages for another channel', () => {
    initProxy();

    emitMessage({
      channel: 'Another_channel',
    });

    expect(postMessage).not.toHaveBeenCalled();
  });
});
