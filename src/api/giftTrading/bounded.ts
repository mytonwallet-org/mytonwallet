/** Enforces a deadline even if an adapter ignores AbortSignal. Late results are discarded. */
export async function boundedRead<T>(parent: AbortSignal, read: (signal: AbortSignal) => Promise<T>, milliseconds = 10000): Promise<T> {
  if (!Number.isSafeInteger(milliseconds) || milliseconds < 1 || milliseconds > 30000) throw Error('Invalid read deadline');
  parent.throwIfAborted();
  const child = new AbortController();
  let rejectStop!: (reason: unknown) => void;
  const stopped = new Promise<never>((_, reject) => { rejectStop = reject; });
  const stop = (reason: unknown) => { child.abort(reason); rejectStop(reason); };
  const abort = () => stop(parent.reason ?? Error('Read cancelled'));
  parent.addEventListener('abort', abort, { once: true });
  const timer = setTimeout(() => stop(Error('Read deadline exceeded')), milliseconds);
  try {
    const value = await Promise.race([Promise.resolve().then(() => { child.signal.throwIfAborted(); return read(child.signal); }), stopped]);
    parent.throwIfAborted(); child.signal.throwIfAborted(); return value;
  } finally { clearTimeout(timer); parent.removeEventListener('abort', abort); }
}

const MAX_RESPONSE_BYTES = 1024 * 1024;
const MAX_RESPONSE_CHUNKS = 8192;

export function jsonResponseSizeAllowed(size: string | null): boolean {
  return size === null || (/^\d{1,10}$/.test(size) && Number(size) <= MAX_RESPONSE_BYTES);
}

/** Bound each read, the total read time, and the amount of work even for empty chunks. */
export async function readBoundedUtf8(
  reader: ReadableStreamDefaultReader<Uint8Array>, signal: AbortSignal, source: string,
): Promise<string> {
  return boundedRead(signal, async scoped => {
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let bytes = 0;
    let chunks = 0;
    let text = '';
    for (;;) {
      const { value, done } = await boundedRead(scoped, () => reader.read());
      if (done) return text + decoder.decode();
      bytes += value.byteLength;
      if (bytes > MAX_RESPONSE_BYTES) throw Error(`${source} response too large`);
      if (++chunks > MAX_RESPONSE_CHUNKS) throw Error(`${source} response has too many chunks`);
      if (value.byteLength) text += decoder.decode(value, { stream: true });
    }
  });
}
