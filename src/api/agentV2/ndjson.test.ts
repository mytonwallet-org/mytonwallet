import { AgentV2StreamTransportError, parseAgentV2Ndjson } from './ndjson';

const RUN_ID = '11111111-1111-4111-8111-111111111111';
const CLIENT_RUN_ID = '22222222-2222-4222-8222-222222222222';
const THREAD_ID = '33333333-3333-4333-8333-333333333333';
const MESSAGE_ID = '44444444-4444-4444-8444-444444444444';

describe('parseAgentV2Ndjson', () => {
  it('keeps transient activity outside the replay cursor and reads historical activity', async () => {
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    const parse = (items: Record<string, unknown>[]) => collect(parseAgentV2Ndjson(stream(items.map((item) => (
      new TextEncoder().encode(`${JSON.stringify(event(item))}\n`)
    ))), binding));
    const first = await parse([
      { type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 },
      { type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown' },
      { type: 'run_activity', sequence: 2, ephemeral: true, code: 'web.searching', status: 'active' },
      { type: 'run_activity', sequence: 2, ephemeral: true, code: 'future.progress', status: 'active' },
    ]);
    expect(first).toHaveLength(3);
    expect(binding.lastSequence).toBe(2);
    expect(binding.rawBySequence.size).toBe(2);
    const resumed = await parse([
      { type: 'run_activity', sequence: 2, ephemeral: true, code: 'web.searching', status: 'completed' },
      { type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: 'Answer' },
      { type: 'run_activity', sequence: 4, code: 'web.searching', status: 'completed' },
      { type: 'message_end', sequence: 5, messageId: MESSAGE_ID, finishReason: 'complete' },
    ]);
    expect(resumed.map(({ type }) => type)).toEqual(['run_activity', 'text_delta', 'run_activity', 'message_end']);
    expect(binding.lastSequence).toBe(5);
    expect(binding.rawBySequence.size).toBe(5);
  });

  it.each([
    { runId: THREAD_ID, sequence: 2 },
    { runId: RUN_ID, sequence: 3 },
  ])('rejects activity with a different run or future anchor: %s', async (invalid) => {
    const binding = { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, lastSequence: 2,
      rawBySequence: new Map<number, string>() };
    const wire = event({ type: 'run_activity', ephemeral: true, code: 'web.searching', status: 'active', ...invalid });
    await expect(collect(parseAgentV2Ndjson(stream([
      new TextEncoder().encode(`${JSON.stringify(wire)}\n`),
    ]), binding))).rejects.toThrow();
    expect(binding.lastSequence).toBe(2);
  });

  it('reconciles transient text across reconnect and durable replay without advancing the draft cursor', async () => {
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    const parse = (items: Record<string, unknown>[]) => collect(parseAgentV2Ndjson(stream(items.map((item) => (
      new TextEncoder().encode(`${JSON.stringify(event(item))}\n`)
    ))), binding));
    const first = await parse([
      { type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 },
      { type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown' },
      { type: 'text_draft', sequence: 2, messageId: MESSAGE_ID, offset: 0, delta: 'Hi 🙂' },
    ]);
    expect(binding.lastSequence).toBe(2);
    const replay = await parse([
      { type: 'text_draft', sequence: 2, messageId: MESSAGE_ID, offset: 0, delta: 'Hi 🙂 there' },
      { type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, offset: 0, delta: 'Hi 🙂 there!' },
      { type: 'message_content_end', sequence: 4, messageId: MESSAGE_ID, createdAt: '2026-09-16T00:00:00.000Z' },
      { type: 'text_draft', sequence: 2, messageId: MESSAGE_ID, offset: 12, delta: 'late' },
      { type: 'message_end', sequence: 5, messageId: MESSAGE_ID, finishReason: 'complete' },
    ]);
    expect([...first, ...replay].flatMap((item) => item.type === 'text_delta' ? [item.delta] : []).join(''))
      .toBe('Hi 🙂 there!');
    expect(binding.lastSequence).toBe(5);
  });

  it('preserves visible drafts when the owner dies and a terminal event reuses the next durable sequence', async () => {
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    const items = [
      { type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 },
      { type: 'message_start', sequence: 2, messageId: MESSAGE_ID, role: 'assistant', contentKind: 'markdown' },
      { type: 'text_draft', sequence: 2, messageId: MESSAGE_ID, offset: 0, delta: 'Partial answer' },
      { type: 'message_end', sequence: 3, messageId: MESSAGE_ID, finishReason: 'run_interrupted' },
    ];
    const events = await collect(parseAgentV2Ndjson(stream(items.map((item) => (
      new TextEncoder().encode(`${JSON.stringify(event(item))}\n`)
    ))), binding));
    expect(events[2]).toMatchObject({ type: 'text_delta', delta: 'Partial answer' });
    expect(events[3]).toMatchObject({ type: 'message_end', finishReason: 'run_interrupted' });
    expect(binding.lastSequence).toBe(3);
  });

  it.each([
    ['**Цена**: 0.000001', '234567 USD. Изменение: −2.75%.'],
    ['**Price**: 9876.', '543210 EUR. Change: +1.25%.'],
  ])('preserves market answer chunks as ordinary Markdown', async (first, second) => {
    const expected = [
      event({ type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 }),
      event({ type: 'text_delta', sequence: 2, messageId: MESSAGE_ID, delta: first }),
      event({ type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: second }),
    ];
    const chunks = expected.map((item) => new TextEncoder().encode(`${JSON.stringify(item)}\n`));
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    expect(await collect(parseAgentV2Ndjson(stream(chunks), binding))).toEqual(expected);
  });

  it.each(['complete', 'cancelled', 'tool_unavailable'])(
    'keeps text and terminal %s after an invalid action', async (reason) => {
      const wire = [
        event({ type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 }),
        event({ type: 'text_delta', sequence: 2, messageId: MESSAGE_ID, delta: 'Saved answer' }),
        event({ type: 'action', sequence: 3, messageId: MESSAGE_ID, action: { kind: 'receive' } }),
        event({ type: 'message_end', sequence: 4, messageId: MESSAGE_ID, finishReason: reason }),
      ];
      const binding: import('./ndjson').AgentV2StreamBinding = {
        clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>(),
      };
      const received = await collect(parseAgentV2Ndjson(stream(wire.map((item) => (
        new TextEncoder().encode(`${JSON.stringify(item)}\n`)
      ))), binding));
      expect(received.map(({ type }) => type)).toEqual(['run_start', 'text_delta', 'message_end']);
      expect(received[1]).toMatchObject({ delta: 'Saved answer' });
      expect(received[2]).toMatchObject({ finishReason: reason });
      expect(binding.incompleteMessageIds?.has(MESSAGE_ID)).toBe(true);
      expect(binding.lastSequence).toBe(4);
    },
  );

  it('handles split UTF-8 boundaries and preserves stream binding', async () => {
    const payload = [
      event({ type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 }),
      event({ type: 'text_delta', sequence: 2, messageId: MESSAGE_ID, delta: 'Привет 👋' }),
    ].map((item) => JSON.stringify(item)).join('\n').concat('\n');
    const bytes = new TextEncoder().encode(payload);
    const emojiOffset = payload.indexOf('👋');
    const split = new TextEncoder().encode(payload.slice(0, emojiOffset)).byteLength + 2;
    const binding: import('./ndjson').AgentV2StreamBinding = {
      clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>(),
    };

    const events = await collect(parseAgentV2Ndjson(stream([bytes.slice(0, split), bytes.slice(split)]), binding));

    expect(events).toHaveLength(2);
    expect(events[1]).toMatchObject({ type: 'text_delta', delta: 'Привет 👋' });
    expect(binding).toMatchObject({ runId: RUN_ID, lastSequence: 2 });
  });

  it('ignores only byte-equivalent replay and rejects gaps or conflicting duplicates', async () => {
    const runStart = JSON.stringify(event({
      type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
    }));
    const binding: import('./ndjson').AgentV2StreamBinding = {
      clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>(),
    };
    await collect(parseAgentV2Ndjson(stream([new TextEncoder().encode(`${runStart}\n`)]), binding));

    expect(await collect(parseAgentV2Ndjson(stream([new TextEncoder().encode(`${runStart}\n`)]), binding))).toEqual([]);
    await expect(collect(parseAgentV2Ndjson(stream([new TextEncoder().encode(`${JSON.stringify(event({
      type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: 'gap',
    }))}\n`)]), binding))).rejects.toThrow('sequence gap');
    await expect(collect(parseAgentV2Ndjson(stream([new TextEncoder().encode(`${JSON.stringify({
      ...JSON.parse(runStart), createdAt: '2026-07-16T00:00:00.000Z',
    })}\n`)]), binding))).rejects.toThrow('conflicting duplicate');
  });

  it('commits ignored events while preserving sequence and replay validation', async () => {
    const runStart = event({
      type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
    });
    const ignored = event({ type: 'future_optional', sequence: 2, payload: { display: true } });
    const delta = event({ type: 'text_delta', sequence: 3, messageId: MESSAGE_ID, delta: 'after extension' });
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    const payload = [runStart, ignored, delta].map((item) => JSON.stringify(item)).join('\n').concat('\n');

    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(payload)]),
      binding,
    ))).resolves.toEqual([runStart, delta]);
    expect(binding.lastSequence).toBe(3);

    const ignoredLine = JSON.stringify(ignored).concat('\n');
    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(ignoredLine)]),
      binding,
    ))).resolves.toEqual([]);
    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(JSON.stringify({ ...ignored, payload: { display: false } }).concat('\n'))]),
      binding,
    ))).rejects.toThrow('conflicting duplicate');
    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(JSON.stringify({ ...ignored, sequence: 5 }).concat('\n'))]),
      binding,
    ))).rejects.toThrow('sequence gap');
  });

  it('does not allow an ignored event to replace run_start', async () => {
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };

    await expect(collect(parseAgentV2Ndjson(stream([new TextEncoder().encode(JSON.stringify(event({
      type: 'future_optional', sequence: 1,
    })).concat('\n'))]), binding))).rejects.toThrow('did not start with run_start');
    expect(binding.lastSequence).toBe(0);
  });

  it('advances the reconnect cursor only after its consumer accepts an event', async () => {
    const runStart = event({
      type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1,
    });
    const delta = event({ type: 'text_delta', sequence: 2, messageId: MESSAGE_ID, delta: 'retry me' });
    const payload = [runStart, delta].map((item) => JSON.stringify(item)).join('\n').concat('\n');
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };
    const iterator = parseAgentV2Ndjson(stream([new TextEncoder().encode(payload)]), binding);

    await expect(iterator.next()).resolves.toMatchObject({ value: runStart, done: false });
    expect(binding.lastSequence).toBe(0);

    await expect(iterator.next()).resolves.toMatchObject({ value: delta, done: false });
    expect(binding.lastSequence).toBe(1);

    await iterator.return(undefined);
    expect(binding.lastSequence).toBe(1);
    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(JSON.stringify({ ...delta, delta: 'changed' }).concat('\n'))]),
      binding,
    ))).rejects.toThrow('conflicting duplicate');
    await expect(collect(parseAgentV2Ndjson(
      stream([new TextEncoder().encode(JSON.stringify(delta).concat('\n'))]),
      binding,
    ))).resolves.toEqual([delta]);
  });

  it('retains at most 256 replay lines', async () => {
    const events = [
      event({ type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 }),
      ...Array.from({ length: 256 }, (_, index) => event({
        type: 'text_delta', sequence: index + 2, messageId: MESSAGE_ID, delta: String(index),
      })),
    ];
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };

    await collect(parseAgentV2Ndjson(stream([
      new TextEncoder().encode(events.map((item) => JSON.stringify(item)).join('\n').concat('\n')),
    ]), binding));

    expect(binding.rawBySequence.size).toBe(256);
    expect(binding.rawBySequence.has(1)).toBe(false);
    expect(binding.rawBySequence.has(257)).toBe(true);
  });

  it('retains at most one MiB of replay lines', async () => {
    const events = [
      event({ type: 'run_start', sequence: 1, clientRunId: CLIENT_RUN_ID, threadId: THREAD_ID, threadRevision: 1 }),
      ...Array.from({ length: 220 }, (_, index) => event({
        type: 'text_delta', sequence: index + 2, messageId: MESSAGE_ID, delta: 'x'.repeat(5000),
      })),
    ];
    const binding: import('./ndjson').AgentV2StreamBinding = {
      clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>(),
    };

    await collect(parseAgentV2Ndjson(stream([
      new TextEncoder().encode(events.map((item) => JSON.stringify(item)).join('\n').concat('\n')),
    ]), binding));

    expect(binding.rawBytes).toBeLessThanOrEqual(1024 * 1024);
    expect(binding.rawBySequence.size).toBeLessThan(220);
  });

  it('classifies reader failures as retryable transport failures', async () => {
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.error(new TypeError('network disconnected'));
      },
    });
    const binding = { clientRunId: CLIENT_RUN_ID, lastSequence: 0, rawBySequence: new Map<number, string>() };

    await expect(collect(parseAgentV2Ndjson(body, binding))).rejects.toBeInstanceOf(AgentV2StreamTransportError);
  });
});

function event(extra: Record<string, unknown>) {
  return { protocolVersion: 3, runId: RUN_ID, ...extra };
}

function stream(chunks: Uint8Array[]) {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      chunks.forEach((chunk) => controller.enqueue(chunk));
      controller.close();
    },
  });
}

async function collect<T>(events: AsyncGenerator<T>) {
  const result: T[] = [];
  for await (const event of events) result.push(event);
  return result;
}
