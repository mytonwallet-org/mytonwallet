export function raceWithAbortSignal<T>(
  task: PromiseLike<T> | (() => PromiseLike<T>),
  signal?: AbortSignal | null,
): Promise<T> {
  if (signal?.aborted) return Promise.reject(getAbortReason(signal));

  const promise = typeof task === 'function' ? task() : task;
  if (!signal) return Promise.resolve(promise);

  return new Promise((resolve, reject) => {
    const handleAbort = () => {
      cleanup();
      reject(getAbortReason(signal));
    };
    const cleanup = () => signal.removeEventListener('abort', handleAbort);
    signal.addEventListener('abort', handleAbort, { once: true });
    void Promise.resolve(promise).then(
      (value) => {
        cleanup();
        resolve(value);
      },
      (err) => {
        cleanup();
        reject(err);
      },
    );
  });
}

export function mergeAbortSignals(...signals: Array<AbortSignal | null | undefined>): {
  signal?: AbortSignal;
  cleanup: () => void;
} {
  const activeSignals = signals.filter((signal): signal is AbortSignal => Boolean(signal));
  if (!activeSignals.length) return { cleanup() {} };
  if (activeSignals.length === 1) return { signal: activeSignals[0], cleanup() {} };

  const controller = new AbortController();
  const listeners = activeSignals.map((signal) => ({
    signal,
    handleAbort: () => abort(signal),
  }));
  const cleanup = () => listeners.forEach(({ signal, handleAbort }) => {
    signal.removeEventListener('abort', handleAbort);
  });
  const abort = (signal: AbortSignal) => {
    cleanup();
    controller.abort(getAbortReason(signal));
  };
  const abortedSignal = activeSignals.find(({ aborted }) => aborted);
  if (abortedSignal) {
    abort(abortedSignal);
  } else {
    listeners.forEach(({ signal, handleAbort }) => {
      signal.addEventListener('abort', handleAbort, { once: true });
    });
  }

  return { signal: controller.signal, cleanup };
}

export function mergeAbortSignalsWithTimeout(
  milliseconds: number,
  ...signals: Array<AbortSignal | null | undefined>
): { signal: AbortSignal; cleanup: () => void } {
  const timeoutController = new AbortController();
  const timeoutId = setTimeout(() => {
    timeoutController.abort(new DOMException('The operation timed out.', 'TimeoutError'));
  }, milliseconds);
  const merged = mergeAbortSignals(timeoutController.signal, ...signals);

  return {
    signal: merged.signal ?? timeoutController.signal,
    cleanup() {
      clearTimeout(timeoutId);
      merged.cleanup();
    },
  };
}

export function pauseWithAbortSignal(milliseconds: number, signal?: AbortSignal | null): Promise<void> {
  if (signal?.aborted) return Promise.reject(getAbortReason(signal));

  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      cleanup();
      resolve();
    }, milliseconds);
    const handleAbort = () => {
      if (!signal) return;
      clearTimeout(timeoutId);
      cleanup();
      reject(getAbortReason(signal));
    };
    const cleanup = () => signal?.removeEventListener('abort', handleAbort);
    signal?.addEventListener('abort', handleAbort, { once: true });
  });
}

export function throwIfAborted(signal?: AbortSignal | null) {
  if (signal?.aborted) throw getAbortReason(signal);
}

export function getAbortReason(signal: AbortSignal) {
  return signal.reason ?? new DOMException('Aborted', 'AbortError');
}
