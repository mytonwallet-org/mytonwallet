export type ClientTimingEvent = {
  traceId: string;
  clockId: string;
  spanId: string;
  parentSpanId?: string;
  operation: string;
  eventSequence: number;
  monotonicMs: number;
  durationMs?: number;
  droppedCount?: number;
  httpStatus?: number;
  outcome?: 'started' | 'success' | 'error' | 'cancelled' | 'interrupted';
  sequence?: number;
  eventType?: string;
  toolName?: string;
};

export type ClientTimingSink = (events: ClientTimingEvent[]) => void;
let sequence = 0;
let clockId: string | undefined;

export function newClientTraceId() {
  return crypto.randomUUID().replace(/-/g, '');
}

export class AgentClientTrace {
  private readonly marked = new Set<string>();
  private rootSpanId?: string;

  constructor(
    readonly traceId: string,
    private readonly sink: ClientTimingSink,
    private readonly parentSpanId?: string,
  ) {}

  transportHeaders(): Record<string, string> {
    return {
      'x-agent-trace-id': this.traceId,
      ...(this.parentSpanId ? { 'x-agent-parent-span-id': this.parentSpanId } : {}),
    };
  }

  mark(operation: string, data: Partial<Pick<ClientTimingEvent, 'sequence' | 'eventType'>> = {}) {
    this.emit({ operation, spanId: newClientTraceId().slice(0, 16), ...data });
  }

  markOnce(operation: string) {
    if (this.marked.has(operation)) return;
    this.marked.add(operation);
    this.mark(operation);
  }

  start(operation: string, data: Pick<ClientTimingEvent, 'toolName'> = {}) {
    const spanId = newClientTraceId().slice(0, 16);
    const start = performance.now();
    let ended = false;
    this.emit({ ...data, operation, spanId, outcome: 'started' });
    if (operation === 'client_request') this.rootSpanId = spanId;
    const end = (outcome: ClientTimingEvent['outcome'] = 'success', httpStatus?: number) => {
      if (ended) return;
      ended = true;
      this.emit({
        ...data,
        operation,
        spanId,
        outcome,
        durationMs: performance.now() - start,
        ...(httpStatus === undefined ? {} : { httpStatus }),
      });
      if (this.rootSpanId === spanId) this.rootSpanId = undefined;
    };
    return Object.assign(end, { trace: new AgentClientTrace(this.traceId, this.sink, spanId) });
  }

  async observe<T>(operation: string, invoke: (trace: AgentClientTrace) => Promise<T>): Promise<T> {
    const end = this.start(operation);
    try {
      const result = await invoke(end.trace);
      if (typeof Response !== 'undefined' && result instanceof Response) {
        end(result.ok ? 'success' : 'error', result.status);
      } else end();
      return result;
    } catch (error) {
      end(error instanceof Error && error.name === 'AbortError' ? 'cancelled' : 'error');
      throw error;
    }
  }

  private emit(data: Pick<ClientTimingEvent, 'operation' | 'spanId'> & Partial<ClientTimingEvent>) {
    try {
      clockId ??= newClientTraceId();
      this.sink([
        {
          ...(this.parentSpanId ? { parentSpanId: this.parentSpanId } : {}),
          ...(this.rootSpanId && data.spanId !== this.rootSpanId ? { parentSpanId: this.rootSpanId } : {}),
          ...data,
          traceId: this.traceId,
          clockId,
          eventSequence: sequence++,
          monotonicMs: performance.now(),
        },
      ]);
    } catch {
      /* Diagnostics cannot interrupt the request */
    }
  }
}

export function createClientTimingSender(baseUrl: string, fetcher: typeof fetch): ClientTimingSink {
  const queue: ClientTimingEvent[] = [];
  let timer: ReturnType<typeof setTimeout> | undefined;
  let sending = false;
  const losses = new Map<string, { event: ClientTimingEvent; count: number }>();
  function dropped(events: ClientTimingEvent[]) {
    for (const event of events) {
      const previous = losses.get(event.traceId);
      losses.set(event.traceId, { event, count: (previous?.count ?? 0) + (event.droppedCount ?? 1) });
    }
    while (losses.size > 32) losses.delete(losses.keys().next().value!);
  }
  function schedule() {
    if (timer || sending || !queue.length) return;
    timer = setTimeout(() => {
      timer = undefined;
      void flush();
    }, 100);
  }
  async function flush() {
    if (sending || !queue.length) return;
    sending = true;
    const reports: ClientTimingEvent[] = [...losses.values()].map(({ event, count }) => ({
      traceId: event.traceId, clockId: clockId ??= newClientTraceId(),
      spanId: newClientTraceId().slice(0, 16), operation: 'client_telemetry_drop',
      eventSequence: sequence++, monotonicMs: performance.now(), droppedCount: count,
    }));
    losses.clear();
    const batch = [...reports, ...queue.splice(0, 100 - reports.length)];
    try {
      const response = await fetcher(`${baseUrl}/dev/telemetry/client-events`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ events: batch }),
        cache: 'no-store',
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) throw new Error('Telemetry rejected');
    } catch {
      // A bounded retry is deduplicated by the development collector
      try {
        const retry = await fetcher(`${baseUrl}/dev/telemetry/client-events`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ events: batch }),
          cache: 'no-store',
          signal: AbortSignal.timeout(5000),
        });
        if (!retry.ok) dropped(batch);
      } catch {
        dropped(batch);
      }
    } finally {
      sending = false;
      schedule();
    }
  }
  return (events) => {
    queue.push(...events);
    if (queue.length > 1000) dropped(queue.splice(0, queue.length - 1000));
    schedule();
  };
}
