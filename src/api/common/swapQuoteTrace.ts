import { IS_AIR_APP } from '../../config';
import { addLog } from '../../util/logs';

type Stage = 'account' | 'config' | 'http' | 'body' | 'batch';

let lastCallId = 0;

/** No request/response values: the same trace is retained in SDK exports and Air's native log. */
export async function traceSwapQuote<T>(
  mode: 'exactIn' | 'exactOut',
  operation: (stage: (name: Stage, status?: number) => void) => Promise<T>,
): Promise<T> {
  const id = ++lastCallId;
  const startedAt = performance.now();
  let stage: Stage = 'account';
  const record = (event: string) => {
    const elapsed = Math.round(performance.now() - startedAt);
    const line = `sdkSwapQuote call=${id} elapsedMs=${elapsed} stage=${stage} ${event}`;
    addLog({ message: line, args: [], level: 'debug' });
    if (IS_AIR_APP) {
      // console.log is persisted by the native bridge, including in release builds.
      // eslint-disable-next-line no-console
      console.log(line);
    }
  };
  record(`start mode=${mode}`);
  const watchdog = setTimeout(() => record('slow'), 10000);
  try {
    const result = await operation((name, status) => {
      stage = name;
      record(`begin${status === undefined ? '' : ` status=${status}`}`);
    });
    record('returned');
    return result;
  } catch (error) {
    record(`failed type=${error instanceof Error ? error.name : 'Error'}`);
    throw error;
  } finally {
    clearTimeout(watchdog);
  }
}
