import type { ApiNetwork } from '../../../types';
import { CHAIN } from './types';

import { APP_VERSION, TON_CONNECT_ANALYTICS_URL } from '../../../../config';
import { generateUuidV7 } from '../../../../util/random';
import { throttle } from '../../../../util/schedulers';
import { getCurrentNetwork } from '../../../common/accounts';
import { getBackendConfigCache, getBackendConfigCacheSync } from '../../../common/cache';

// We emit TON Connect telemetry to `analytics.ton.org` as the wallet subsystem (see `analytics-spec`).

export type TonConnectEventName =
  | 'wallet-connect-request-received'
  | 'wallet-connect-request-ui-displayed'
  | 'wallet-connect-accepted'
  | 'wallet-connect-rejected'
  | 'wallet-connect-response-sent'
  | 'wallet-transaction-request-received'
  | 'wallet-transaction-confirmation-ui-displayed'
  | 'wallet-transaction-accepted'
  | 'wallet-transaction-declined'
  | 'wallet-transaction-sent'
  | 'wallet-sign-data-request-received'
  | 'wallet-sign-data-confirmation-ui-displayed'
  | 'wallet-sign-data-accepted'
  | 'wallet-sign-data-declined'
  | 'wallet-sign-data-sent'
  | 'bridge-client-connect-started'
  | 'bridge-client-connect-established'
  | 'bridge-client-connect-error'
  | 'bridge-client-message-sent'
  | 'bridge-client-message-received'
  | 'bridge-client-message-decode-error'
  | 'js-bridge-call'
  | 'js-bridge-response'
  | 'js-bridge-error';

export type TonConnectVerificationResult = 'unknown' | 'ok' | 'warning' | 'danger';

export type TonConnectRequestType = 'sendTransaction' | 'signData' | 'disconnect' | 'connect' | 'connect_error';

// Per-event fields a caller may provide; the shared envelope fields are filled by `recordTonConnectEvent`.
export interface TonConnectEventFields {
  // Normally auto-filled by the recorder from the flow context (or a session fallback). A caller may pass it
  // explicitly for a flow event emitted before its context exists (e.g. the on-arrival `*-request-received`).
  network_id?: string;
  client_id?: string;
  wallet_id?: string;
  manifest_json_url?: string;
  origin_url?: string;
  dapp_name?: string;
  callback_return_action?: string;
  is_ton_addr?: boolean;
  is_ton_proof?: boolean;
  proof_payload_size?: number;
  verification_result?: TonConnectVerificationResult;
  emulation_success?: boolean;
  decline_reason?: string;
  payload?: string;
  normalized_hash?: string;
  signed_boc?: string;
  error_code?: number;
  error_message?: string;
  bridge_url?: string;
  message_id?: string;
  request_type?: TonConnectRequestType;
  encrypted_message_hash?: string;
  bridge_connect_duration?: number;
  bridge_key?: string;
  js_bridge_method?: string;
}

// Fields that scope a single connect/transaction/sign flow, shared by all its events via `promiseId`.
export type TonConnectFlowContext = {
  trace_id: string;
  network_id: string;
} & Pick<TonConnectEventFields,
'client_id' | 'wallet_id' | 'manifest_json_url' | 'origin_url' | 'dapp_name'
| 'callback_return_action' | 'verification_result'
>;

export type RecordTonConnectEventInput = TonConnectEventFields & {
  event_name: TonConnectEventName;
  // Resolves the shared flow context (`trace_id`, `network_id`, dapp/session fields); not sent on the wire.
  promiseId?: string;
  // Explicit trace for events not tied to a flow (e.g. a js-bridge call paired with its response).
  trace_id?: string;
};

const WALLET_APP_NAME = 'MyTonWallet';

// A fresh per-launch session id; the spec leaves `user_id` empty for wallets, so this only correlates one session.
// Generated lazily on the first recorded event, so a launch that never enables analytics does no work. Uses
// `generateUuidV7` (crypto.getRandomValues) rather than `crypto.randomUUID`, which is not available on every
// SDK runtime (Worker/ServiceWorker/WKWebView/Android WebView) — same reason the embedded bridge guards it.
let sessionUserId: string | undefined;

function getSessionUserId() {
  sessionUserId ??= generateUuidV7();
  return sessionUserId;
}

const TON_CONNECT_REQUEST_TYPES = new Set<TonConnectRequestType>([
  'sendTransaction', 'signData', 'disconnect', 'connect', 'connect_error',
]);

// Narrows an attacker-controllable bridge `method` string to the known union, or `undefined` when unrecognized,
// instead of force-casting an arbitrary string into the telemetry payload.
export function toTonConnectRequestType(method: string): TonConnectRequestType | undefined {
  return TON_CONNECT_REQUEST_TYPES.has(method as TonConnectRequestType)
    ? (method as TonConnectRequestType)
    : undefined;
}

// Terminal user-decision events: at most one accepted-or-declined/rejected should be recorded per flow.
// A failed password/MFA/signing attempt keeps the confirm UI open, so a flow can fire `*-accepted` and then,
// once the user gives up and cancels, `*-declined`/`*-rejected` for the same `promiseId`. Keeping only the first
// decision keeps the accept/decline funnel consistent across platforms (web, Electron, iOS and Android all route
// their UI events through here), instead of relying on a per-platform guard.
const TON_CONNECT_DECISION_EVENTS = new Set<TonConnectEventName>([
  'wallet-connect-accepted', 'wallet-connect-rejected',
  'wallet-transaction-accepted', 'wallet-transaction-declined',
  'wallet-sign-data-accepted', 'wallet-sign-data-declined',
]);

const flowContexts = new Map<string, TonConnectFlowContext>();

// Promise ids that already recorded a terminal decision. Kept independent of the flow-context lifetime (the
// handler's `finally` drops the context as soon as it returns) because a late `*-declined` can cross the worker
// boundary after the `*-accepted` flow has already finished; the guard must still see the earlier decision.
// Bounded with FIFO eviction so it cannot grow without limit over a long session.
const MAX_RECORDED_DECISIONS = 256;
const recordedDecisionPromiseIds = new Set<string>();

function markDecisionRecorded(promiseId: string) {
  if (recordedDecisionPromiseIds.size >= MAX_RECORDED_DECISIONS) {
    const oldest = recordedDecisionPromiseIds.values().next().value;
    if (oldest !== undefined) {
      recordedDecisionPromiseIds.delete(oldest);
    }
  }
  recordedDecisionPromiseIds.add(promiseId);
}

export function setTonConnectFlowContext(promiseId: string, context: TonConnectFlowContext) {
  flowContexts.set(promiseId, context);
}

export function getTonConnectFlowContext(promiseId: string) {
  return flowContexts.get(promiseId);
}

export function clearTonConnectFlowContext(promiseId: string) {
  flowContexts.delete(promiseId);
}

// Reports the final wallet→dapp event of a flow. The shared context is dropped by the caller's `finally`, not
// here, so it stays available to a late UI event (e.g. a slow native `*-accepted`) until the handler returns.
export function finishTonConnectFlow(
  promiseId: string,
  responseEventName: TonConnectEventName,
  fields?: TonConnectEventFields,
) {
  void recordTonConnectEvent({ event_name: responseEventName, promiseId, ...fields });
}

export function toTonConnectNetworkId(network?: ApiNetwork): string {
  return network === 'testnet' ? CHAIN.TESTNET : CHAIN.MAINNET;
}

export async function recordTonConnectEvent(input: RecordTonConnectEventInput) {
  // Gate on the cached backend flag, synchronously, before any `await`. Three states:
  //  - loaded + disabled  → drop (the default for opt-in telemetry);
  //  - loaded + enabled   → build and enqueue for the next batch;
  //  - not loaded yet     → build and hold in `preConfigBuffer`, released once the flag is known. This keeps
  //    startup events (e.g. `bridge-client-connect-started`, fired during SSE setup before the config poll
  //    resolves) from being systematically dropped.
  const config = getBackendConfigCacheSync();
  if (config && !config.isTonConnectAnalyticsEnabled) {
    return;
  }

  const { promiseId, trace_id: explicitTraceId, ...fields } = input;

  // Drop a second terminal decision for the same flow (see `TON_CONNECT_DECISION_EVENTS`).
  if (promiseId && TON_CONNECT_DECISION_EVENTS.has(input.event_name)) {
    if (recordedDecisionPromiseIds.has(promiseId)) {
      return;
    }
    markDecisionRecorded(promiseId);
  }

  // Read the flow context synchronously (before the `await` below) so a concurrent context clear cannot race it.
  const context = promiseId ? flowContexts.get(promiseId) : undefined;
  const traceId = explicitTraceId ?? context?.trace_id ?? generateUuidV7();
  const networkId = fields.network_id ?? context?.network_id ?? await getFallbackNetworkId();

  const event: AnyLiteral = {
    event_id: generateUuidV7(),
    subsystem: 'wallet',
    client_environment: 'wallet',
    version: APP_VERSION,
    wallet_app_name: WALLET_APP_NAME,
    wallet_app_version: APP_VERSION,
    user_id: getSessionUserId(),
    client_timestamp: nowInSeconds(),
    ...context,
    ...fields,
    // Resolve the correlation fields last so they win deterministically over `...context`/`...fields`: an explicit
    // input value, then the flow context, then a live fallback. `network_id` is omitted entirely (rather than sent
    // as `undefined`) when it cannot be resolved, so the collector never receives an empty network tag.
    trace_id: traceId,
    ...(networkId !== undefined ? { network_id: networkId } : undefined),
  };

  if (config) {
    enqueueEvent(event);
  } else {
    preConfigBuffer?.push(event);
  }
}

// --- Transport: batching + pre-config buffer ---

// The collector accepts an array body, so events are coalesced into one POST instead of one-per-event (a single
// dapp interaction emits ~5-7 events). Flushed on a trailing throttle, or immediately once a batch fills up.
const FLUSH_THROTTLE_MS = 1000;
const MAX_BATCH_SIZE = 50;
let eventBatch: AnyLiteral[] = [];

const scheduleFlush = throttle(flushEvents, FLUSH_THROTTLE_MS, false);

function enqueueEvent(event: AnyLiteral) {
  eventBatch.push(event);
  if (eventBatch.length >= MAX_BATCH_SIZE) {
    flushEvents();
  } else {
    scheduleFlush();
  }
}

function flushEvents() {
  if (!eventBatch.length) {
    return;
  }
  const events = eventBatch;
  eventBatch = [];
  void postEvents(events);
}

// Events recorded before the backend config has loaded are held here, then flushed (if enabled) or discarded
// once the flag is known. `undefined` after that point means "config resolved, use the synchronous gate".
let preConfigBuffer: AnyLiteral[] | undefined = [];

void getBackendConfigCache().then((config) => {
  const buffered = preConfigBuffer ?? [];
  preConfigBuffer = undefined;
  if (config?.isTonConnectAnalyticsEnabled) {
    buffered.forEach(enqueueEvent);
  }
});

function postEvents(events: AnyLiteral[]) {
  return fetch(`${TON_CONNECT_ANALYTICS_URL}/events`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Client-Timestamp': nowInSeconds().toString(),
    },
    body: JSON.stringify(events),
  }).catch(() => undefined);
}

async function getCurrentNetworkId() {
  return toTonConnectNetworkId(await getCurrentNetwork());
}

// Best-effort network tag for events not bound to a flow (bridge-client-* and js-bridge-*). Flow events carry the
// network snapshotted in their context; these do not, and the SSE bridge is not tied to a single dapp's network, so
// the live account network is the best available tag. Cached with a short TTL so a chatty bridge does not do a
// storage read per message, while still refreshing within seconds of a mainnet/testnet switch. Failures are
// swallowed so the fire-and-forget telemetry path never rejects at the bare `void recordTonConnectEvent(...)` sites.
const NETWORK_ID_TTL_MS = 5000;
let cachedNetworkId: string | undefined;
let cachedNetworkIdAt = 0;

async function getFallbackNetworkId() {
  if (cachedNetworkId !== undefined && Date.now() - cachedNetworkIdAt <= NETWORK_ID_TTL_MS) {
    return cachedNetworkId;
  }
  try {
    cachedNetworkId = await getCurrentNetworkId();
    cachedNetworkIdAt = Date.now();
    return cachedNetworkId;
  } catch {
    return undefined;
  }
}

function nowInSeconds() {
  return Math.floor(Date.now() / 1000);
}
