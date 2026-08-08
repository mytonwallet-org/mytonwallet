import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type { AgentMessage } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';
import type { AgentError } from '../../../util/agent/agentApi';
import type { UseAgentMessagesResult } from './useAgentMessages';

import { createAgentStream as createAgentStreamMocked } from '../../../util/agent/agentApi';
import {
  loadAgentMessages,
  saveAgentMessages,
} from '../../../util/agent/agentStorage';
import { pause, waitFor } from '../../../util/schedulers';
import useAgentMessages from './useAgentMessages';

jest.mock('../../../global', () => {
  const actual = jest.requireActual('../../../global');

  return {
    ...actual,
    getActions: () => ({ setAgentMeta: jest.fn() }),
    getGlobal: () => ({ settings: { theme: 'light' } }),
  };
});
jest.mock('../../../global/selectors', () => ({
  selectCurrentAccountId: () => 'account-id',
  selectCurrentAccountState: () => undefined,
  selectCurrentAccountTokens: () => [],
  selectOrderedAccounts: () => [],
}));
jest.mock('../../../util/agent/agentApi', () => ({
  buildRequestContext: jest.fn(() => ({})),
  createAgentStream: jest.fn(),
}));
jest.mock('../../../util/agent/agentStorage', () => ({
  clearAgentChat: jest.fn(() => Promise.resolve()),
  loadAgentMessages: jest.fn(),
  saveAgentMessages: jest.fn(() => Promise.resolve()),
}));

interface StreamCallbacks {
  onFirstChunk: (text: string) => void;
  onNextChunk: (text: string) => void;
  onComplete: (text: string) => void;
  onError: (error: AgentError) => void;
}

const lang = Object.assign((key: string) => `Error: ${key}`, { code: 'en' as const }) as LangFn;
const loadAgentMessagesMock = jest.mocked(loadAgentMessages);
const saveAgentMessagesMock = jest.mocked(saveAgentMessages);
const createAgentStreamMock = jest.mocked(createAgentStreamMocked);

let root: HTMLDivElement;
let latestController: UseAgentMessagesResult | undefined;
let streamCallbacks: StreamCallbacks | undefined;

beforeEach(() => {
  root = document.createElement('div');
  document.body.appendChild(root);
  latestController = undefined;
  streamCallbacks = undefined;
  loadAgentMessagesMock.mockReset();
  loadAgentMessagesMock.mockResolvedValue([]);
  saveAgentMessagesMock.mockClear();
  createAgentStreamMock.mockReset();
  createAgentStreamMock.mockImplementation((_text, _context, callbacks) => {
    streamCallbacks = callbacks;
    return { abort: jest.fn() };
  });
});

afterEach(() => {
  TeactDOM.render(undefined, root);
  root.remove();
});

describe('useAgentMessages streaming presentation', () => {
  it('hydrates completed messages without creating a reveal session', async () => {
    loadAgentMessagesMock.mockResolvedValue(buildHistory());

    renderHarness();
    await waitForHydration();

    expect(latestController?.messages).toEqual(buildHistory());
    expect(latestController?.textRevealPresentations).toEqual({});
  });

  it('consumes a fresh reveal session before completion and excludes transient state from storage', async () => {
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('Question');
    await pause(20);

    const presentation = latestController!.textRevealPresentations[2];
    expect(presentation).toMatchObject({
      status: 'active',
      shouldRevealFromStart: true,
    });
    expect(latestController?.messages[1]).toMatchObject({
      id: 2,
      isTyping: true,
      isStreaming: true,
    });

    latestController!.consumeTextRevealSession(2, 'stale-key');
    await pause(20);
    expect(latestController?.textRevealPresentations[2]).toEqual(presentation);

    latestController!.consumeTextRevealSession(2, presentation.key);
    await pause(20);
    expect(latestController?.textRevealPresentations[2]).toEqual({
      ...presentation,
      shouldRevealFromStart: false,
    });

    await waitForStreamStart();
    streamCallbacks!.onFirstChunk('Fast');
    streamCallbacks!.onComplete('Fast answer');
    await pause(20);

    expect(latestController?.messages[1]).toMatchObject({
      id: 2,
      text: 'Fast answer',
      isOutgoing: false,
    });
    expect(latestController?.messages[1]).not.toHaveProperty('isStreaming');
    expect(latestController?.textRevealPresentations[2].status).toBe('active');
    expect(saveAgentMessagesMock).toHaveBeenCalledWith(latestController?.messages);
    expect(saveAgentMessagesMock.mock.calls[0][0][1]).not.toHaveProperty('isStreaming');

    latestController!.settleTextRevealSession(2, presentation.key);
    await pause(20);

    expect(latestController?.textRevealPresentations[2]).toEqual({
      ...presentation,
      status: 'settled',
      shouldRevealFromStart: false,
    });
  });

  it('creates a fresh session for an edited response', async () => {
    loadAgentMessagesMock.mockResolvedValue(buildHistory());
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('Edited question', 1);
    await pause(20);
    const presentation = latestController!.textRevealPresentations[2];

    expect(latestController?.messages).toEqual([
      expect.objectContaining({ id: 1, text: 'Edited question', isOutgoing: true }),
      expect.objectContaining({ id: 2, isTyping: true, isStreaming: true }),
    ]);
    expect(presentation.key).toMatch(/^0:2:/);

    await waitForStreamStart();
    streamCallbacks!.onComplete('Edited answer');
    await pause(20);
    latestController!.sendMessage('Edited again', 1);
    await pause(20);

    expect(latestController!.textRevealPresentations[2].key).not.toBe(presentation.key);
    expect(latestController!.textRevealPresentations[2]).toMatchObject({
      status: 'active',
      shouldRevealFromStart: true,
    });
  });

  it('shows an error immediately after a partial stream and terminates its presentation', async () => {
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('Question');
    await waitForStreamStart();
    streamCallbacks!.onFirstChunk('Partial answer');
    await pause(20);
    streamCallbacks!.onError('AgentErrorResponseFailed' as never);
    await pause(20);

    expect(latestController?.textRevealPresentations[2]).toMatchObject({
      status: 'error',
      shouldRevealFromStart: false,
    });
    expect(latestController?.messages[1]).toMatchObject({
      text: 'Error: AgentErrorResponseFailed',
      isOutgoing: false,
    });
    expect(latestController?.messages[1]).not.toHaveProperty('isStreaming');
    expect(saveAgentMessagesMock.mock.calls[0][0][1]).not.toHaveProperty('isStreaming');
  });

  it('keeps completed visual drains independent when the next response starts', async () => {
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('First question');
    await waitForStreamStart();
    streamCallbacks!.onComplete('First answer');
    await pause(20);

    const firstPresentation = latestController!.textRevealPresentations[2];
    expect(firstPresentation.status).toBe('active');

    streamCallbacks = undefined;
    latestController!.sendMessage('Second question');
    await pause(20);

    expect(latestController!.textRevealPresentations[2]).toEqual(firstPresentation);
    expect(latestController!.textRevealPresentations[4]).toMatchObject({
      status: 'active',
      shouldRevealFromStart: true,
    });
  });

  it('prunes superseded presentation records when editing an earlier question', async () => {
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('First question');
    await waitForStreamStart();
    streamCallbacks!.onComplete('First answer');
    await pause(20);
    const firstKey = latestController!.textRevealPresentations[2].key;

    streamCallbacks = undefined;
    latestController!.sendMessage('Second question');
    await waitForStreamStart();
    streamCallbacks!.onComplete('Second answer');
    await pause(20);
    expect(Object.keys(latestController!.textRevealPresentations)).toEqual(['2', '4']);

    latestController!.sendMessage('Edited first question', 1);
    await pause(20);

    expect(Object.keys(latestController!.textRevealPresentations)).toEqual(['2']);
    expect(latestController!.textRevealPresentations[2].key).not.toBe(firstKey);
  });

  it('clears all in-memory presentations with the chat', async () => {
    renderHarness();
    await waitForHydration();

    latestController!.sendMessage('Question');
    await pause(20);
    expect(latestController!.textRevealPresentations[2]).toBeDefined();

    latestController!.clearChat();
    await pause(20);

    expect(latestController!.messages).toEqual([]);
    expect(latestController!.textRevealPresentations).toEqual({});
  });
});

function Harness() {
  latestController = useAgentMessages({ lang });
  return undefined;
}

function renderHarness() {
  TeactDOM.render(<Harness />, root);
}

async function waitForHydration() {
  expect(await waitFor(
    () => latestController?.isInitialLoadComplete === true,
    10,
    20,
  )).toBe(true);
}

async function waitForStreamStart() {
  expect(await waitFor(
    () => streamCallbacks !== undefined,
    20,
    20,
  )).toBe(true);
}

function buildHistory(): AgentMessage[] {
  return [
    {
      id: 1,
      text: 'Question',
      isOutgoing: true,
      timestamp: 1,
    },
    {
      id: 2,
      text: 'Answer',
      isOutgoing: false,
      timestamp: 2,
    },
  ];
}
