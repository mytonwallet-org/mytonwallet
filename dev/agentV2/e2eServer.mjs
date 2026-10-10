import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';

const DIST_DIR = join(process.cwd(), 'dist');
const FIXED_TIME = '2026-08-11T09:00:00.000Z';
const THREAD_ID = '44444444-4444-4444-8444-444444444444';
const WALLET_SESSION_ID = '77777777-7777-4777-8777-777777777777';
const CONTENT_TYPES = {
  '.css': 'text/css; charset=utf-8',
  '.gif': 'image/gif',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.webmanifest': 'application/manifest+json',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};
let state = createState();
const pendingResponses = new Set();
let completePendingRun;

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? '127.0.0.1:1235'}`);
    const body = await readJsonBody(request);

    if (url.pathname.startsWith('/__agent-v2-control/')) {
      handleControlRequest(request, response, url, body);
      return;
    }

    if (url.pathname.startsWith('/api/v2/')) {
      handleAgentRequest(request, response, url, body);
      return;
    }

    if (url.pathname === '/__agent-v2-seed') {
      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      response.end('<!doctype html><html><body>Agent V2 E2E seed</body></html>');
      return;
    }

    serveStatic(response, url.pathname);
  } catch (error) {
    writeJson(response, 500, {
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

server.listen(1235, '127.0.0.1', () => {
  process.stdout.write('Agent V2 E2E server listening at http://127.0.0.1:1235\n');
});

process.on('SIGINT', closeServer);
process.on('SIGTERM', closeServer);

function createState(scenario = 'conversation') {
  return {
    scenario,
    requests: [],
    runBodies: [],
    cancelBodies: [],
    clearBodies: [],
    runCount: 0,
    quotaRequestCount: 0,
    wasQuotaDenied: false,
    revision: 1,
    messages: scenario === 'pagination' ? createLatestMessages() : [],
    olderMessages: scenario === 'pagination' ? createOlderMessages() : [],
  };
}

function handleControlRequest(request, response, url, body) {
  if (request.method === 'POST' && url.pathname === '/__agent-v2-control/reset') {
    releasePendingResponses();
    state = createState(typeof body?.scenario === 'string' ? body.scenario : 'conversation');
    writeJson(response, 200, publicState());
    return;
  }

  if (request.method === 'POST' && url.pathname === '/__agent-v2-control/complete-run') {
    if (!completePendingRun) {
      writeJson(response, 409, { error: 'No pending run.' });
      return;
    }
    completePendingRun();
    completePendingRun = undefined;
    writeJson(response, 200, publicState());
    return;
  }

  if (request.method === 'GET' && url.pathname === '/__agent-v2-control/state') {
    writeJson(response, 200, publicState());
    return;
  }

  writeJson(response, 404, { error: 'Unknown Agent V2 E2E control endpoint.' });
}

function handleAgentRequest(request, response, url, body) {
  state.requests.push({
    method: request.method,
    path: `${url.pathname}${url.search}`,
    ...(body === undefined ? {} : { body }),
  });

  if (request.method === 'POST' && url.pathname === '/api/v2/device-token') {
    writeJson(response, 200, {
      protocolVersion: 3,
      deviceId: body.deviceId,
      deviceToken: `adt_v2.${'a'.repeat(43)}`,
      expiresAt: '2099-08-11T09:00:00.000Z',
    });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/v2/hints') {
    writeJson(response, 200, {
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v1',
      items: [],
    });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/v2/capabilities') {
    writeJson(response, 200, {
      protocolVersion: 3,
      walletQuery: { status: 'disabled' },
    });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/v2/availability') {
    writeJson(response, 200, state.scenario === 'capacity-error' && state.runCount > 0
      ? {
        protocolVersion: 3,
        state: 'capacity_exhausted',
        resetAt: '2099-08-12T09:00:00.000Z',
      }
      : { protocolVersion: 3, state: 'available' });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/v2/quota') {
    state.quotaRequestCount += 1;
    writeJson(response, 200, { protocolVersion: 3, quota: getQuota() });
    return;
  }

  if (request.method === 'GET' && url.pathname === '/api/v2/threads/default') {
    writeJson(response, 200, { protocolVersion: 3, thread: threadSummary(), created: false });
    return;
  }

  if (request.method === 'GET' && url.pathname === `/api/v2/threads/${THREAD_ID}/messages`) {
    const isOlderPage = url.searchParams.get('cursor') === 'older';
    const messages = isOlderPage ? state.olderMessages : state.messages;
    writeJson(response, 200, {
      protocolVersion: 3,
      thread: threadSummary(),
      messages,
      ...(!isOlderPage && state.olderMessages.length ? { nextCursor: 'older' } : {}),
    });
    return;
  }

  if (request.method === 'POST' && url.pathname === `/api/v2/threads/${THREAD_ID}/clear`) {
    state.clearBodies.push(body);
    state.messages = [];
    state.olderMessages = [];
    state.revision += 1;
    writeJson(response, 200, { protocolVersion: 3, thread: threadSummary(), duplicate: false });
    return;
  }

  if (request.method === 'POST' && url.pathname === '/api/v2/runs') {
    handleRun(response, body);
    return;
  }

  const cancelMatch = url.pathname.match(/^\/api\/v2\/runs\/([^/]+)\/cancel$/u);
  if (request.method === 'POST' && cancelMatch) {
    state.cancelBodies.push({ runId: cancelMatch[1], body });
    if (state.scenario === 'wallet-switch') {
      holdResponse(response);
      return;
    }
    writeJson(response, 200, {
      protocolVersion: 3,
      runId: cancelMatch[1],
      state: 'cancelled',
      lastSequence: 3,
    });
    return;
  }

  writeJson(response, 404, {
    protocolVersion: 3,
    error: { code: 'invalid_request', retryable: false },
  });
}

function handleRun(response, body) {
  state.runCount += 1;
  state.runBodies.push(body);

  if (state.scenario === 'quota-retry' && state.runCount === 1) {
    state.wasQuotaDenied = true;
    writeJson(response, 429, {
      protocolVersion: 3,
      error: {
        code: 'user_quota_exhausted',
        retryable: true,
        resetAt: '2099-08-12T09:00:00.000Z',
        quota: exhaustedQuota(),
      },
    });
    return;
  }

  if (state.scenario === 'admission-retry' && state.runCount <= 3) {
    writeJson(response, 503, {
      protocolVersion: 3,
      error: {
        code: 'provider_unavailable',
        retryable: true,
      },
    });
    return;
  }

  if (state.scenario === 'terminal-action-error' && state.runCount > 1 && state.runCount <= 4) {
    writeJson(response, 503, {
      protocolVersion: 3,
      error: {
        code: 'provider_unavailable',
        retryable: true,
      },
    });
    return;
  }

  const runId = uuid(100 + state.runCount);
  const messageId = uuid(200 + state.runCount);
  const userMessage = body.input?.message;
  const answerParts = getAnswerParts(userMessage?.text);
  const answerText = answerParts.filter((part) => typeof part === 'string').join('');
  const answerLinks = answerParts.filter((part) => typeof part !== 'string' && !part.messageId).map(({ link }) => link);
  const activityEvents = state.scenario === 'run-activity' ? [
    event(runId, { type: 'run_activity', sequence: 2, code: 'web.searching', status: 'active' }),
    event(runId, { type: 'run_activity', sequence: 3, code: 'web.searching', status: 'completed' }),
    event(runId, { type: 'run_activity', sequence: 4, code: 'web.reading_sources', status: 'active' }),
    event(runId, { type: 'run_activity', sequence: 5, code: 'web.reading_sources', status: 'completed' }),
    event(runId, { type: 'run_activity', sequence: 6, code: 'data.reading_market', status: 'active' }),
  ] : [];
  const messageStartSequence = activityEvents.length + 2;
  const baseEvents = [
    event(runId, {
      type: 'run_start',
      sequence: 1,
      clientRunId: body.clientRunId,
      threadId: THREAD_ID,
      threadRevision: state.revision,
    }),
    ...activityEvents,
    event(runId, {
      type: 'message_start',
      sequence: messageStartSequence,
      messageId,
      role: 'assistant',
      contentKind: 'markdown',
    }),
    ...answerParts.map((part, index) => event(runId, typeof part === 'string' ? {
      type: 'text_delta',
      sequence: index + messageStartSequence + 1,
      messageId,
      delta: part,
    } : {
      type: 'text_link',
      sequence: index + messageStartSequence + 1,
      messageId,
      ...part,
    })),
  ];

  const continuedDeltas = getContinuedDeltas();
  if (continuedDeltas) {
    writeNdjsonHeaders(response);
    baseEvents.forEach((item) => response.write(`${JSON.stringify(item)}\n`));
    holdResponse(response);
    completePendingRun = () => {
      let sequence = baseEvents.length + 1;
      state.revision += 1;
      persistCompletedRun(userMessage, messageId, runId, answerText + continuedDeltas.join(''), [], answerLinks);
      response.end([
        ...continuedDeltas.map((delta) => event(runId, { type: 'text_delta', sequence: sequence++, messageId, delta })),
        event(runId, { type: 'thread', sequence: sequence++, thread: threadSummary(2) }),
        event(runId, { type: 'message_end', sequence, messageId, finishReason: 'complete' }),
      ].map((item) => `${JSON.stringify(item)}\n`).join(''));
    };
    return;
  }

  if (state.scenario === 'terminal-action-error') {
    persistFailedRun(userMessage, messageId, runId, answerText, {
      code: 'provider_error',
      retryable: true,
    });
    writeNdjson(response, [
      ...baseEvents,
      actionEvent(runId, messageId, 4, receiveAction(body)),
      event(runId, {
        type: 'error',
        sequence: 5,
        messageId,
        code: 'provider_error',
        retryable: true,
      }),
      actionEvent(runId, messageId, 6, openDappAction()),
      event(runId, { type: 'thread', sequence: 7, thread: nextThreadSummary(2) }),
      event(runId, { type: 'message_end', sequence: 8, messageId, finishReason: 'complete' }),
    ]);
    return;
  }

  if (state.scenario === 'capacity-error') {
    const error = {
      code: 'agent_capacity_exhausted',
      retryable: true,
      resetAt: '2099-08-12T09:00:00.000Z',
    };
    persistFailedRun(userMessage, messageId, runId, answerText, error);
    writeNdjson(response, [
      ...baseEvents,
      event(runId, {
        type: 'error',
        sequence: answerParts.length + messageStartSequence + 1,
        messageId,
        ...error,
      }),
    ]);
    return;
  }

  const extraEvents = [];
  let sequence = answerParts.length + messageStartSequence + 1;
  if (state.scenario === 'receive-navigation') {
    extraEvents.push(actionEvent(runId, messageId, sequence++, receiveAction(body)));
  }

  state.revision += 1;
  const events = [
    ...baseEvents,
    ...extraEvents,
    event(runId, { type: 'thread', sequence: sequence++, thread: threadSummary(2) }),
    event(runId, { type: 'message_end', sequence, messageId, finishReason: 'complete' }),
  ];
  persistCompletedRun(userMessage, messageId, runId, answerText, extraEvents, answerLinks);
  writeNdjsonSlowly(response, events, state.scenario === 'run-activity' ? 650 : 150);
}

function persistCompletedRun(userMessage, messageId, runId, answerText, extraEvents, links = []) {
  if (userMessage?.id && userMessage.text) {
    state.messages.push({
      id: userMessage.id,
      threadId: THREAD_ID,
      role: 'user',
      status: 'complete',
      content: { kind: 'markdown', text: userMessage.text },
      createdAt: FIXED_TIME,
      runId,
    });
  }

  const actions = extraEvents
    .filter((item) => item.type === 'action')
    .map((item) => projectPersistedAction(item.action));
  const followups = extraEvents
    .filter((item) => item.type === 'followups')
    .flatMap((item) => item.items);
  state.messages.push({
    id: messageId,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'complete',
    content: { kind: 'markdown', text: answerText, ...(links.length ? { links } : {}) },
    createdAt: FIXED_TIME,
    runId,
    ...(actions.length ? { actions } : {}),
    ...(followups.length ? { followups } : {}),
  });
}

function persistFailedRun(userMessage, messageId, runId, answerText, error) {
  if (userMessage?.id && userMessage.text) {
    state.messages.push({
      id: userMessage.id,
      threadId: THREAD_ID,
      role: 'user',
      status: 'complete',
      content: { kind: 'markdown', text: userMessage.text },
      createdAt: FIXED_TIME,
      runId,
    });
  }

  state.messages.push({
    id: messageId,
    threadId: THREAD_ID,
    role: 'assistant',
    status: 'error',
    content: { kind: 'markdown', text: answerText },
    createdAt: FIXED_TIME,
    runId,
    error,
  });
}

function projectPersistedAction(action) {
  switch (action.kind) {
    case 'receive':
      return {
        id: action.id,
        kind: action.kind,
        labelCode: action.labelCode,
        title: action.title,
        effect: action.effect,
        localDraftRequired: action.localDraftRequired,
        requiresConfirmation: action.requiresConfirmation,
      };
    case 'openSettings':
      return { ...action, schemaVersion: 3 };
    default:
      throw new Error(`Unsupported Agent action: ${action.kind}`);
  }
}

function receiveAction(runBody) {
  const walletContext = runBody.walletContext;
  return {
    id: uuid(301),
    kind: 'receive',
    labelCode: 'open_receive',
    title: 'Open receive',
    effect: 'open_receive',
    contextBinding: {
      sessionId: walletContext?.sessionId ?? WALLET_SESSION_ID,
      revision: walletContext?.revision ?? 1,
      activeAccountRef: walletContext?.activeAccount?.accountRef ?? 'current',
      activeNetwork: walletContext?.activeNetwork ?? 'ton',
    },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function openDappAction() {
  return {
    id: uuid(302),
    schemaVersion: 1,
    kind: 'openDapp',
    labelCode: 'open_external_link',
    title: 'Open app',
    url: 'https://fragment.com/',
    requiresConfirmation: true,
  };
}

function actionEvent(runId, messageId, sequence, action) {
  return event(runId, { type: 'action', sequence, messageId, action });
}

function event(runId, value) {
  return { protocolVersion: 3, runId, ...value };
}

// A string is a text delta; an object is the rest of a `text_link` event, published before its label
function getAnswerParts(text) {
  if (state.scenario === 'answer-links') {
    return ['Read the ', { link: { textOffset: 9, textLength: 8, url: 'https://docs.ton.org/develop' } }, 'TON '];
  }
  if (state.scenario === 'receive-navigation') {
    return [
      'Choose a wallet action or open ',
      { link: { textOffset: 31, textLength: 10, url: 'mtw://settings/appearance' } },
      'Appearance',
      '.',
    ];
  }
  if (state.scenario === 'answer-link-events') {
    return [
      'Open ',
      { link: { textOffset: 5, textLength: 8, url: 'https://ton.org/' } },
      'TON site',
      ', ',
      { link: { textOffset: 15, textLength: 4, url: 'javascript:alert(1)' } },
      'docs',
      ' and ',
      { messageId: 'not-a-message-id', link: { textOffset: 24, textLength: 4, url: 'https://ton.org/dev' } },
      'blog',
      '.',
    ];
  }
  return [getAnswerText(text)];
}

// Text deltas a held run streams once the test completes it
function getContinuedDeltas() {
  if (state.scenario === 'wallet-switch') return [' The response continued after switching wallets.'];
  if (state.scenario === 'answer-links') return ['docs', ' before you build.'];
  return undefined;
}

function getAnswerText(text) {
  if (state.scenario === 'quota-retry') return `Quota request completed: ${text}`;
  if (state.scenario === 'admission-retry') return `Recovered response: ${text}`;
  if (state.scenario === 'terminal-action-error') return 'This response will fail.';
  if (state.scenario === 'capacity-error') return 'A partial response was started.';
  if (state.scenario === 'wallet-switch') return 'Partial response before switching wallets.';
  return `Deterministic response: ${text}`;
}

function getQuota() {
  if (state.wasQuotaDenied && state.quotaRequestCount === 1) return exhaustedQuota();
  return {
    limit: 20,
    used: Math.min(state.runCount, 20),
    remaining: Math.max(0, 20 - state.runCount),
    resetAt: '2099-08-12T09:00:00.000Z',
  };
}

function exhaustedQuota() {
  return {
    limit: 20,
    used: 20,
    remaining: 0,
    resetAt: '2026-08-12T09:00:00.000Z',
  };
}

function threadSummary(messageIncrement = 0) {
  return {
    id: THREAD_ID,
    revision: state.revision,
    createdAt: FIXED_TIME,
    updatedAt: FIXED_TIME,
    lastActivityAt: FIXED_TIME,
    messageCount: state.messages.length + messageIncrement,
  };
}

function nextThreadSummary(messageIncrement) {
  return { ...threadSummary(messageIncrement), revision: state.revision + 1 };
}

function createLatestMessages() {
  return [
    persistedMessage(21, 'user', 'Latest seeded question'),
    persistedMessage(22, 'assistant', 'Latest seeded answer'),
  ];
}

function createOlderMessages() {
  return [
    persistedMessage(11, 'user', 'Oldest seeded question'),
    persistedMessage(12, 'assistant', 'Oldest seeded answer'),
  ];
}

function persistedMessage(id, role, text) {
  return {
    id: uuid(id),
    threadId: THREAD_ID,
    role,
    status: 'complete',
    content: { kind: 'markdown', text },
    createdAt: FIXED_TIME,
  };
}

function uuid(value) {
  return `00000000-0000-4000-8000-${String(value).padStart(12, '0')}`;
}

function publicState() {
  return {
    scenario: state.scenario,
    requests: state.requests,
    runBodies: state.runBodies,
    cancelBodies: state.cancelBodies,
    clearBodies: state.clearBodies,
    runCount: state.runCount,
    quotaRequestCount: state.quotaRequestCount,
    messageHydrations: state.messageHydrations,
    revision: state.revision,
    messages: state.messages,
    olderMessages: state.olderMessages,
    pendingResponseCount: pendingResponses.size,
  };
}

async function readJsonBody(request) {
  if (request.method === 'GET' || request.method === 'HEAD') return undefined;

  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  if (!chunks.length) return undefined;

  const text = Buffer.concat(chunks).toString('utf8');
  return text ? JSON.parse(text) : undefined;
}

function writeJson(response, statusCode, value) {
  response.writeHead(statusCode, {
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
  });
  response.end(`${JSON.stringify(value)}\n`);
}

function writeNdjson(response, events) {
  writeNdjsonHeaders(response);
  response.end(`${events.map((item) => JSON.stringify(item)).join('\n')}\n`);
}

async function writeNdjsonSlowly(response, events, delayMs) {
  writeNdjsonHeaders(response);
  for (const item of events) {
    response.write(`${JSON.stringify(item)}\n`);
    await wait(delayMs);
  }
  response.end();
}

function writeNdjsonHeaders(response) {
  response.writeHead(200, {
    'Cache-Control': 'no-store',
    'Content-Type': 'application/x-ndjson; charset=utf-8',
  });
}

function holdResponse(response) {
  pendingResponses.add(response);
  response.once('close', () => pendingResponses.delete(response));
}

function releasePendingResponses() {
  completePendingRun = undefined;
  pendingResponses.forEach((response) => response.destroy());
  pendingResponses.clear();
}

function serveStatic(response, pathname) {
  const relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const safePath = normalize(relativePath).replace(/^(\.\.(\/|\\|$))+/, '');
  let filePath = join(DIST_DIR, safePath);
  if (!existsSync(filePath) || !statSync(filePath).isFile()) filePath = join(DIST_DIR, 'index.html');

  response.writeHead(200, {
    'Cache-Control': 'no-store',
    'Content-Type': CONTENT_TYPES[extname(filePath)] ?? 'application/octet-stream',
  });
  createReadStream(filePath).pipe(response);
}

function wait(delay) {
  return new Promise((resolve) => setTimeout(resolve, delay));
}

function closeServer() {
  releasePendingResponses();
  server.close(() => process.exit(0));
}
