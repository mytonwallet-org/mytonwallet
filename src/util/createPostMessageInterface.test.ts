import { createReverseIFrameInterface } from './createPostMessageInterface';

const CHANNEL = 'test-channel';
const TRUSTED_ORIGIN = 'https://trusted.example';

describe('createReverseIFrameInterface', () => {
  let cleanup: NoneToVoidFunction | undefined;
  let target: Window;
  let postMessage: jest.Mock;

  beforeEach(() => {
    postMessage = jest.fn();
    target = { postMessage } as unknown as Window;
  });

  afterEach(() => {
    cleanup?.();
    cleanup = undefined;
  });

  it('should ignore calls from a navigated cross-origin iframe', async () => {
    const method = jest.fn();
    cleanup = createReverseIFrameInterface({ method }, TRUSTED_ORIGIN, target, CHANNEL);

    window.dispatchEvent(new MessageEvent('message', {
      origin: 'https://attacker.example',
      data: {
        channel: CHANNEL,
        type: 'callMethod',
        messageId: '1',
        name: 'method',
        args: [],
      },
    }));
    await Promise.resolve();

    expect(method).not.toHaveBeenCalled();
    expect(postMessage).not.toHaveBeenCalled();
  });

  it('should allow calls from the iframe origin', async () => {
    const method = jest.fn().mockResolvedValue('ok');
    cleanup = createReverseIFrameInterface({ method }, TRUSTED_ORIGIN, target, CHANNEL);

    window.dispatchEvent(new MessageEvent('message', {
      origin: TRUSTED_ORIGIN,
      data: {
        channel: CHANNEL,
        type: 'callMethod',
        messageId: '2',
        name: 'method',
        args: ['payload'],
      },
    }));
    await Promise.resolve();

    expect(method).toHaveBeenCalledWith('payload');
    expect(postMessage).toHaveBeenCalledWith({
      channel: CHANNEL,
      type: 'methodResponse',
      messageId: '2',
      response: 'ok',
    }, TRUSTED_ORIGIN);
  });
});
