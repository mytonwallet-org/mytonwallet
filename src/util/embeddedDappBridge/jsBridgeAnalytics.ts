import type { RecordTonConnectEventInput } from '../../api/dappProtocols/adapters/tonConnect/analytics';

import { TONCONNECT_WALLET_JSBRIDGE_KEY } from '../../config';
import { generateUuidV7 } from '../random';

// Reports `js-bridge-*` analytics around an injected-bridge method call (in-app browser and extension providers).

const BRIDGE_KEY = TONCONNECT_WALLET_JSBRIDGE_KEY;

type EmitJsBridgeEvent = (input: RecordTonConnectEventInput) => void;

export function trackJsBridgeMethod<Args extends unknown[], Result>(
  method: string,
  emit: EmitJsBridgeEvent,
  fn: (...args: Args) => Promise<Result>,
): (...args: Args) => Promise<Result> {
  return async (...args: Args) => {
    // The call and its paired response/error share one trace so the two halves can be joined in analytics.
    const traceId = generateUuidV7();
    emit({
      event_name: 'js-bridge-call', js_bridge_method: method, bridge_key: BRIDGE_KEY, trace_id: traceId,
    });

    try {
      const result = await fn(...args);
      // The in-app-browser bridge resolves an error-shaped object instead of throwing, so a rejected/failed
      // request would otherwise be recorded as a success. Inspect the resolved value, not just exceptions.
      const errorMessage = extractJsBridgeError(method, result);
      emit(errorMessage !== undefined
        ? {
          event_name: 'js-bridge-error',
          js_bridge_method: method,
          bridge_key: BRIDGE_KEY,
          trace_id: traceId,
          error_message: errorMessage,
        }
        : {
          event_name: 'js-bridge-response', js_bridge_method: method, bridge_key: BRIDGE_KEY, trace_id: traceId,
        });
      return result;
    } catch (err) {
      emit({
        event_name: 'js-bridge-error',
        js_bridge_method: method,
        bridge_key: BRIDGE_KEY,
        trace_id: traceId,
        error_message: err instanceof Error ? err.message : String(err),
      });
      throw err;
    }
  };
}

// A TON Connect bridge result is an error when `send` resolves `{ error: { message } }` or `connect` resolves
// `{ event: 'connect_error', payload: { message } }`. Returns the message, or `undefined` for a successful result.
// `restoreConnection` is excluded from the `connect_error` case: it returns `connect_error` as its normal
// "no existing session" outcome on essentially every dApp page load, which is not a bridge error.
function extractJsBridgeError(method: string, result: unknown): string | undefined {
  if (!result || typeof result !== 'object') {
    return undefined;
  }

  const { error, event, payload } = result as {
    error?: { message?: string };
    event?: string;
    payload?: { message?: string };
  };

  if (error) {
    return error.message ?? 'Error';
  }
  if (event === 'connect_error' && method !== 'restoreConnection') {
    return payload?.message ?? 'Connect error';
  }
  return undefined;
}

export function wrapJsBridgeMethods<T extends object>(methods: T, emit: EmitJsBridgeEvent): T {
  return Object.fromEntries(
    Object.entries(methods).map(([method, fn]) => [
      method,
      trackJsBridgeMethod(method, emit, fn as (...args: unknown[]) => Promise<unknown>),
    ]),
  ) as T;
}
