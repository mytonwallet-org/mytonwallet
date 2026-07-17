/// <reference types="jest" />

import { ReadableStream } from 'node:stream/web';

jest.mock('./agentStore', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn().mockResolvedValue('conversation-id'),
    setItem: jest.fn(),
    removeItem: jest.fn(),
  },
}));

import { createAgentStream } from './agentApi';

describe('createAgentStream', () => {
  const originalFetch = window.fetch;

  afterEach(() => {
    Object.defineProperty(window, 'fetch', {
      configurable: true,
      writable: true,
      value: originalFetch,
    });

    jest.clearAllMocks();
  });

  it('uses window.fetch to stream responses', async () => {
    const fallbackFetch = jest.fn().mockResolvedValue(createStreamingResponse('hello from fetch'));

    Object.defineProperty(window, 'fetch', {
      configurable: true,
      writable: true,
      value: fallbackFetch,
    });

    await expectStreamCompletion('hello from fetch');

    expect(fallbackFetch).toHaveBeenCalledTimes(1);
  });
});

function createStreamingResponse(text: string) {
  const encoder = new TextEncoder();

  return {
    ok: true,
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(encoder.encode(text));
        controller.close();
      },
    }),
  } as unknown as Response;
}

function expectStreamCompletion(expectedText: string) {
  return new Promise<void>((resolve, reject) => {
    createAgentStream('Hello', {} as any, {
      onFirstChunk: jest.fn(),
      onNextChunk: jest.fn(),
      onComplete: (accumulated) => {
        expect(accumulated).toBe(expectedText);
        resolve();
      },
      onError: (error) => {
        reject(new Error(`Unexpected stream error: ${error}`));
      },
    });
  });
}
