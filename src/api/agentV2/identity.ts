import type { Storage } from '../storages/types';
import type { AgentClientTrace } from './developmentTelemetry';
import type { AgentThreadSummaryV2, AgentUserQuotaV2, AgentV2ErrorCode } from './protocol/types';

import { mergeAbortSignals, mergeAbortSignalsWithTimeout } from '../../util/abortSignal';
import { logDebugError } from '../../util/logs';
import contractManifest from './generated/manifest.json';
import {
  decodeAgentV2ApiError,
  decodeAgentV2DeviceToken,
} from './protocol/transportContracts';
import { AgentV2ContractError } from './protocol/wireReader';

export const AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY = 'agentV2DeviceIdentity';
const TOKEN_PATTERN = /^adt_v2\.[A-Za-z0-9_-]{43}$/u;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const TOKEN_EXPIRY_SKEW_MS = 60_000;
// Bounds a request that gets no response, which a filtering network can hold open indefinitely
export const AGENT_V2_REQUEST_TIMEOUT_MS = 20_000;
const HTTP_REQUEST_FAILED_MESSAGE = 'Agent request failed.';
// Every request states its protocol, including the bodyless ones, so the server can tell an outdated client to update
const AGENT_PROTOCOL_ACCEPT = `application/json; agent-protocol=${contractManifest.protocolVersion}`;

interface AgentV2DeviceIdentity {
  version: 1;
  deviceId: string;
  deviceToken: string;
  expiresAt: string;
}

export class AgentV2HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: AgentV2ErrorCode,
    message: string,
    readonly retryable: boolean,
    readonly retryAfterMs?: number,
    readonly resetAt?: string,
    readonly quota?: AgentUserQuotaV2,
    readonly currentThread?: AgentThreadSummaryV2,
  ) {
    super(message);
    this.name = 'AgentV2HttpError';
  }
}

export interface AgentV2IdentityDependencies {
  storage: Storage;
  baseUrl: string;
  fetch: typeof fetch;
  now?: () => number;
  randomUuid?: () => string;
  requestTimeoutMs?: number;
}

export class AgentV2IdentityService {
  private readonly now: () => number;
  private readonly randomUuid: () => string;
  private readonly requestTimeoutMs: number;
  private readonly lifecycleController = new AbortController();
  private currentIdentity?: AgentV2DeviceIdentity;
  private issuance?: Promise<AgentV2DeviceIdentity>;

  constructor(private readonly dependencies: AgentV2IdentityDependencies) {
    this.now = dependencies.now ?? Date.now;
    this.randomUuid = dependencies.randomUuid ?? (() => crypto.randomUUID());
    this.requestTimeoutMs = dependencies.requestTimeoutMs ?? AGENT_V2_REQUEST_TIMEOUT_MS;
  }

  async authenticatedFetch(
    input: string,
    init: RequestInit = {},
    {
      shouldSkipUnauthorizedRecovery = false,
      trace,
    }: { shouldSkipUnauthorizedRecovery?: boolean; trace?: AgentClientTrace } = {},
  ): Promise<Response> {
    if (trace) {
      const headers = new Headers(init.headers);
      headers.set('x-agent-trace-id', trace.traceId);
      init = { ...init, headers };
    }
    this.assertActive(init.signal);
    let identity = await (trace ? trace.observe('client_auth', (child) => this.getOrIssue(child)) : this.getOrIssue());
    this.assertActive(init.signal);
    let response = await (trace
      ? trace.observe('client_http', (child) => this.request(input, init, identity.deviceToken, child))
      : this.request(input, init, identity.deviceToken));
    this.assertActive(init.signal);

    if (response.status === 401 && !shouldSkipUnauthorizedRecovery) {
      identity = await (trace
        ? trace.observe('client_auth', (child) => this.recoverAfterUnauthorized(identity, child))
        : this.recoverAfterUnauthorized(identity));
      this.assertActive(init.signal);
      response = await (trace
        ? trace.observe('client_http', (child) => this.request(input, init, identity.deviceToken, child))
        : this.request(input, init, identity.deviceToken));
      this.assertActive(init.signal);
    }

    return response;
  }

  async destroy({
    shouldClearPersistentIdentity = false,
  }: { shouldClearPersistentIdentity?: boolean } = {}) {
    this.lifecycleController.abort();
    const issuance = this.issuance;
    this.currentIdentity = undefined;
    this.issuance = undefined;
    if (issuance) await issuance.catch(() => undefined);
    if (shouldClearPersistentIdentity) {
      await this.dependencies.storage.removeItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY);
    }
  }

  private async getOrIssue(trace?: AgentClientTrace) {
    this.assertActive();
    if (this.currentIdentity && this.isUsable(this.currentIdentity)) return this.currentIdentity;

    const stored = await this.read();
    this.assertActive();
    if (this.currentIdentity && this.isUsable(this.currentIdentity)) return this.currentIdentity;
    if (stored && this.isUsable(stored)) {
      this.currentIdentity = stored;
      return stored;
    }
    return this.issue(stored?.deviceId ?? this.randomUuid(), trace);
  }

  private async recoverAfterUnauthorized(rejectedIdentity: AgentV2DeviceIdentity, trace?: AgentClientTrace) {
    this.assertActive();
    if (
      this.currentIdentity
      && this.isUsable(this.currentIdentity)
      && this.currentIdentity.deviceToken !== rejectedIdentity.deviceToken
    ) {
      return this.currentIdentity;
    }

    const stored = await this.read();
    this.assertActive();
    if (
      this.currentIdentity
      && this.isUsable(this.currentIdentity)
      && this.currentIdentity.deviceToken !== rejectedIdentity.deviceToken
    ) {
      return this.currentIdentity;
    }
    if (
      stored
      && this.isUsable(stored)
      && stored.deviceToken !== rejectedIdentity.deviceToken
    ) {
      this.currentIdentity = stored;
      return stored;
    }

    return this.issue(rejectedIdentity.deviceId, trace);
  }

  private issue(deviceId: string, trace?: AgentClientTrace): Promise<AgentV2DeviceIdentity> {
    this.assertActive();
    if (this.issuance) return this.issuance;

    const operation = this.performIssue(deviceId, trace).finally(() => {
      if (this.issuance === operation) this.issuance = undefined;
    });
    this.issuance = operation;
    return operation;
  }

  private async performIssue(deviceId: string, trace?: AgentClientTrace): Promise<AgentV2DeviceIdentity> {
    // Issuance is shared by every waiting request, so it carries its own deadline instead of any caller's
    const { signal, cleanup } = mergeAbortSignalsWithTimeout(this.requestTimeoutMs, this.lifecycleController.signal);
    try {
      const send = (child?: AgentClientTrace) => this.dependencies.fetch(`${this.dependencies.baseUrl}/device-token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: AGENT_PROTOCOL_ACCEPT, ...child?.transportHeaders() },
        body: JSON.stringify({ protocolVersion: 3, deviceId }),
        cache: 'no-store',
        signal,
      });
      const response = await (trace ? trace.observe('client_http', send) : send());
      this.assertActive();
      if (!response.ok) {
        // Issuance is the first call the Agent makes, so its refusal is what the user sees as a chat
        // that will not open - and the screen shows a generic failure regardless of the reason. The
        // status and the host that answered are what separate "this build is too old" (426) from
        // "this host serves no V2 at all" (404) from a rate limit (429); without them the three are
        // one symptom. Neither value is user data.
        const origin = originOf(this.dependencies.baseUrl);
        logDebugError(`AgentV2 device token refused: status=${response.status} origin=${origin}`);
        throw await decodeHttpError(response);
      }
      const result = decodeAgentV2DeviceToken(await response.json());
      this.assertActive();
      const identity: AgentV2DeviceIdentity = {
        version: 1,
        deviceId: result.deviceId,
        deviceToken: result.deviceToken,
        expiresAt: result.expiresAt,
      };
      await this.dependencies.storage.setItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY, JSON.stringify(identity));
      this.assertActive();
      this.currentIdentity = identity;
      return identity;
    } finally {
      cleanup();
    }
  }

  private isUsable(identity: AgentV2DeviceIdentity) {
    return Date.parse(identity.expiresAt) > this.now() + TOKEN_EXPIRY_SKEW_MS;
  }

  private async request(input: string, init: RequestInit, token: string, trace?: AgentClientTrace) {
    const headers = new Headers(init.headers);
    headers.set('Authorization', `Bearer ${token}`);
    headers.set('Accept', AGENT_PROTOCOL_ACCEPT);
    for (const [key, value] of Object.entries(trace?.transportHeaders() ?? {})) headers.set(key, value);
    const { signal, cleanup } = mergeAbortSignals(init.signal, this.lifecycleController.signal);
    try {
      return await this.dependencies.fetch(input, { ...init, headers, signal });
    } finally {
      cleanup();
    }
  }

  private async read(): Promise<AgentV2DeviceIdentity | undefined> {
    const stored = await this.dependencies.storage.getItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY);
    try {
      const value = typeof stored === 'string' ? JSON.parse(stored) as Partial<AgentV2DeviceIdentity> : stored;
      if (
        value?.version !== 1
        || !UUID_PATTERN.test(value.deviceId ?? '')
        || !TOKEN_PATTERN.test(value.deviceToken ?? '')
        || !Number.isFinite(Date.parse(value.expiresAt ?? ''))
      ) {
        if (stored !== undefined) {
          await this.dependencies.storage.removeItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY);
        }
        return undefined;
      }
      return value as AgentV2DeviceIdentity;
    } catch {
      await this.dependencies.storage.removeItem(AGENT_V2_DEVICE_IDENTITY_STORAGE_KEY);
      return undefined;
    }
  }

  private assertActive(signal?: AbortSignal | null) {
    if (this.lifecycleController.signal.aborted) {
      throw new Error('Agent V2 identity is destroyed');
    }
    if (signal?.aborted) {
      throw signal.reason ?? new DOMException('Aborted', 'AbortError');
    }
  }
}

export async function decodeHttpError(response: Response): Promise<AgentV2HttpError> {
  try {
    const result = decodeAgentV2ApiError(await response.json());
    return new AgentV2HttpError(
      response.status,
      result.error.code,
      HTTP_REQUEST_FAILED_MESSAGE,
      result.error.retryable,
      result.error.retryAfterMs,
      result.error.resetAt,
      result.error.quota,
      result.error.currentThread,
    );
  } catch (error) {
    if (response.status === 413 && (error instanceof SyntaxError || error instanceof AgentV2ContractError)) {
      return new AgentV2HttpError(response.status, 'invalid_request', HTTP_REQUEST_FAILED_MESSAGE, false);
    }
    if ((response.status === 408 || response.status >= 500)
      && (error instanceof SyntaxError || error instanceof AgentV2ContractError)) {
      return new AgentV2HttpError(response.status, 'provider_unavailable', HTTP_REQUEST_FAILED_MESSAGE, true);
    }
    throw error;
  }
}

// The Agent host is baked into the bundle, so a log line that omits it cannot be matched to a
// deployment later. Only the origin is taken: the path carries the protocol segment and nothing
// user-specific, but there is no reason to widen what a log keeps.
function originOf(baseUrl: string): string {
  try {
    return new URL(baseUrl).origin;
  } catch {
    return baseUrl;
  }
}
