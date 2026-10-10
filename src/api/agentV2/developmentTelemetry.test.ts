import { AgentClientTrace, type ClientTimingEvent, createClientTimingSender } from './developmentTelemetry';

describe('Agent development timings', () => {
  const originalResponse = globalThis.Response;
  beforeEach(() => {
    globalThis.Response = class {
      readonly status: number;
      readonly ok: boolean;
      constructor(_body: unknown, init: ResponseInit) {
        this.status = init.status ?? 200;
        this.ok = this.status < 400;
      }
    } as typeof Response;
  });
  afterEach(() => {
    globalThis.Response = originalResponse;
  });
  afterEach(() => jest.restoreAllMocks());

  it('links nested operations and records failed HTTP status without altering the response', async () => {
    const events: ClientTimingEvent[] = [];
    let clock = 0;
    jest.spyOn(performance, 'now').mockImplementation(() => clock);
    const trace = new AgentClientTrace('a'.repeat(32), (batch) => events.push(...batch));
    const endRequest = trace.start('client_request');
    const response = new Response('{}', { status: 429 });
    await trace.observe('client_preparation', async (preparation) => {
      clock = 10;
      const result = await preparation.observe('client_http', () => {
        clock = 70;
        return Promise.resolve(response);
      });
      expect(result).toBe(response);
    });
    clock = 100;
    endRequest('error');
    const request = events.find((event) => event.operation === 'client_request' && event.outcome === 'started')!;
    const preparation = events.find(
      (event) => event.operation === 'client_preparation' && event.outcome === 'started',
    )!;
    const http = events.find((event) => event.operation === 'client_http' && event.durationMs !== undefined)!;
    expect(preparation.parentSpanId).toBe(request.spanId);
    expect(http).toMatchObject({ parentSpanId: preparation.spanId, durationMs: 60, outcome: 'error', httpStatus: 429 });
    expect(events.at(-1)).toMatchObject({ durationMs: 100, outcome: 'error' });
  });

  it('reports bounded queue losses without copying request content', async () => {
    jest.useFakeTimers();
    const fetcher = jest.fn().mockResolvedValue({ ok: true });
    const send = createClientTimingSender('http://localhost/api/v2', fetcher);
    const trace = new AgentClientTrace('a'.repeat(32), send);
    try {
      for (let index = 0; index < 1003; index += 1) trace.mark('client_event_received');
      await jest.advanceTimersByTimeAsync(100);
      const first = JSON.parse(fetcher.mock.calls[0]![1].body);
      expect(first.events).toHaveLength(100);
      expect(first.events[0]).toMatchObject({ operation: 'client_telemetry_drop', droppedCount: 3 });
      expect(first.events.every((event: ClientTimingEvent) => event.traceId === 'a'.repeat(32))).toBe(true);
      await jest.runAllTimersAsync();
    } finally {
      jest.useRealTimers();
    }
  });

  it('records cancellation once and survives an unavailable diagnostic sink', async () => {
    const events: ClientTimingEvent[] = [];
    const trace = new AgentClientTrace('a'.repeat(32), (batch) => events.push(...batch));
    const error = new DOMException('cancelled', 'AbortError');
    await expect(trace.observe('client_http', () => Promise.reject(error))).rejects.toBe(error);
    expect(events.filter((event) => event.durationMs !== undefined)).toEqual([
      expect.objectContaining({ outcome: 'cancelled' }),
    ]);
    const unavailable = new AgentClientTrace('b'.repeat(32), () => {
      throw new Error('sink failed');
    });
    await expect(unavailable.observe('client_http', () => Promise.resolve('ok'))).resolves.toBe('ok');
  });
});
