import type { AgentClientTrace } from './developmentTelemetry';
import type {
  AgentAvailabilityResponseV2,
  AgentProblemReportCapabilityV1,
  AgentUserQuotaResponseV2,
} from './protocol/types';
import type { AgentV2ClientUpdate, AgentV2Hints } from './types';
import type { AgentV2WalletSession } from './walletSession';

import { logDebugError } from '../../util/logs';
import {
  decodeAgentV2Availability,
  decodeAgentV2FeatureCapabilities,
  decodeAgentV2Hints,
  decodeAgentV2UserQuota,
} from './protocol/transportContracts';

const FEATURE_CAPABILITIES_CACHE_MS = 5 * 60_000;
const UTC_DAY_MS = 24 * 60 * 60_000;
const MAX_TIMER_DELAY_MS = 2_147_483_647;

interface AgentV2RuntimeProbesDependencies {
  baseUrl: string;
  walletSession: AgentV2WalletSession;
  getJson: <T>(url: string, decoder: (value: unknown) => T, init?: RequestInit, trace?: AgentClientTrace) => Promise<T>;
  onUpdate: (update: AgentV2ClientUpdate) => void;
  now: () => number;
}

export class AgentV2RuntimeProbes {
  private readonly lifecycleController = new AbortController();
  private featureCapabilitiesExpiresAt = 0;
  private featureCapabilitiesPromise?: Promise<void>;
  private problemReportStatus: AgentProblemReportCapabilityV1['status'] = 'disabled';
  private hasAvailability = false;
  private availabilityPromise?: Promise<void>;
  private availabilityTimer?: ReturnType<typeof setTimeout>;
  private availabilityGeneration = 0;
  private hasUserQuota = false;
  private userQuotaPromise?: Promise<void>;
  private userQuotaTimer?: ReturnType<typeof setTimeout>;

  constructor(private readonly dependencies: AgentV2RuntimeProbesDependencies) {}

  destroy() {
    this.lifecycleController.abort();
    this.featureCapabilitiesExpiresAt = 0;
    this.featureCapabilitiesPromise = undefined;
    this.problemReportStatus = 'disabled';
    this.clearAvailability();
    this.clearUserQuota();
  }

  async getHints(langCode?: string, trace?: AgentClientTrace): Promise<AgentV2Hints> {
    this.assertActive();
    const query = langCode ? `?langCode=${encodeURIComponent(langCode)}` : '';
    const [result] = await Promise.all([
      this.getJson(`${this.dependencies.baseUrl}/hints${query}`, decodeAgentV2Hints, trace),
      this.ensureFeatureCapabilities(trace),
    ]);
    this.assertActive();
    while (true) {
      const host = this.dependencies.walletSession.snapshot().host;
      await this.ensureFeatureCapabilities(trace);
      this.assertActive();
      if (this.dependencies.walletSession.snapshot().host !== host) continue;
      const { capabilities, walletContext } = this.dependencies.walletSession.buildContext();
      const supportsWalletRead = walletContext.mode === 'wallet'
        && this.dependencies.walletSession.isWalletQueryAvailable();
      const supportsReceiveAction = capabilities.supportedActions.includes('receive');
      return {
        ...result,
        items: result.items.filter(({ requiredCapabilities }) => (
          !requiredCapabilities || requiredCapabilities.every((requiredCapability) => (
            requiredCapability === 'wallet_read' ? supportsWalletRead : supportsReceiveAction
          ))
        )),
      };
    }
  }

  private async probeFeatureCapabilities(trace?: AgentClientTrace) {
    this.assertActive();
    try {
      const result = await this.getJson(
        `${this.dependencies.baseUrl}/capabilities`,
        decodeAgentV2FeatureCapabilities, trace,
      );
      this.assertActive();
      this.dependencies.walletSession.updateFeatureCapabilities(result);
      this.problemReportStatus = result.problemReport.status;
      if (result.walletQuery.status === 'available' && !this.dependencies.walletSession.isWalletQueryAvailable()) {
        logDebugError('AgentV2 wallet filter catalog differs from the server; wallet reads are off');
      }
    } catch {
      if (this.lifecycleController.signal.aborted) return;
      this.dependencies.walletSession.updateFeatureCapabilities();
      this.problemReportStatus = 'disabled';
    } finally {
      if (!this.lifecycleController.signal.aborted) {
        this.featureCapabilitiesExpiresAt = (this.dependencies.now?.() ?? Date.now())
          + FEATURE_CAPABILITIES_CACHE_MS;
      }
    }
  }

  ensureFeatureCapabilities(trace?: AgentClientTrace): Promise<void> {
    const now = this.dependencies.now?.() ?? Date.now();
    if (now >= this.featureCapabilitiesExpiresAt && !this.featureCapabilitiesPromise) {
      const pending = this.probeFeatureCapabilities(trace).finally(() => {
        if (this.featureCapabilitiesPromise === pending) {
          this.featureCapabilitiesPromise = undefined;
        }
      });
      this.featureCapabilitiesPromise = pending;
    }
    return this.featureCapabilitiesPromise ?? Promise.resolve();
  }

  isProblemReportAvailable() {
    return this.problemReportStatus === 'available';
  }

  /** The next check asks the server again instead of answering from the cache */
  expireFeatureCapabilities() {
    this.featureCapabilitiesExpiresAt = 0;
  }

  ensureAvailability(): Promise<void> {
    if (!this.availabilityPromise) {
      const pending = this.probeAvailability().finally(() => {
        if (this.availabilityPromise === pending) this.availabilityPromise = undefined;
      });
      this.availabilityPromise = pending;
    }
    return this.availabilityPromise;
  }

  ensureUserQuota(): Promise<void> {
    if (!this.userQuotaPromise) {
      const pending = this.probeUserQuota().finally(() => {
        if (this.userQuotaPromise === pending) this.userQuotaPromise = undefined;
      });
      this.userQuotaPromise = pending;
    }
    return this.userQuotaPromise;
  }

  refreshAvailability(): Promise<void> {
    if (this.lifecycleController.signal.aborted) return Promise.resolve();
    if (!this.hasAvailability && !this.availabilityPromise) return Promise.resolve();
    const availabilityGeneration = ++this.availabilityGeneration;
    const previous = this.availabilityPromise ?? Promise.resolve();
    const pending = previous.then(() => {
      if (availabilityGeneration !== this.availabilityGeneration) return;
      return this.probeAvailability(availabilityGeneration);
    }).finally(() => {
      if (this.availabilityPromise === pending) this.availabilityPromise = undefined;
    });
    this.availabilityPromise = pending;
    return pending;
  }

  refreshUserQuota(): Promise<void> {
    if (this.lifecycleController.signal.aborted) return Promise.resolve();
    if (!this.hasUserQuota && !this.userQuotaPromise) return Promise.resolve();
    const previous = this.userQuotaPromise ?? Promise.resolve();
    const pending = previous.then(() => this.probeUserQuota()).finally(() => {
      if (this.userQuotaPromise === pending) this.userQuotaPromise = undefined;
    });
    this.userQuotaPromise = pending;
    return pending;
  }

  private async probeUserQuota() {
    if (this.lifecycleController.signal.aborted) return;
    try {
      const result = await this.getJson(`${this.dependencies.baseUrl}/quota`, decodeAgentV2UserQuota);
      this.assertActive();
      this.hasUserQuota = true;
      this.applyUserQuota(result);
    } catch {
      // Admission remains authoritative if the optional quota probe is temporarily unreachable.
    }
  }

  applyUserQuota(response?: AgentUserQuotaResponseV2) {
    if (this.lifecycleController.signal.aborted) return;
    if (this.userQuotaTimer) {
      clearTimeout(this.userQuotaTimer);
      this.userQuotaTimer = undefined;
    }
    if (!response) {
      this.emitUpdate({ kind: 'userQuotaChanged' });
      return;
    }

    const { quota } = response;
    this.emitUpdate({ kind: 'userQuotaChanged', quota });
    if (this.lifecycleController.signal.aborted) return;
    const resetAt = Date.parse(quota.resetAt);
    if (!Number.isFinite(resetAt)) return;
    this.userQuotaTimer = setTimeout(() => {
      if (this.lifecycleController.signal.aborted) return;
      this.userQuotaTimer = undefined;
      this.applyUserQuota({
        protocolVersion: 3,
        quota: {
          limit: quota.limit,
          used: 0,
          remaining: quota.limit,
          resetAt: new Date(resetAt + UTC_DAY_MS).toISOString(),
        },
      });
      void this.probeUserQuota();
    }, Math.min(Math.max(0, resetAt - this.now()), MAX_TIMER_DELAY_MS));
  }

  private async probeAvailability(availabilityGeneration = this.availabilityGeneration) {
    if (
      this.lifecycleController.signal.aborted
      || availabilityGeneration !== this.availabilityGeneration
    ) return;
    try {
      const result = await this.getJson(`${this.dependencies.baseUrl}/availability`, decodeAgentV2Availability);
      this.assertActive();
      if (availabilityGeneration !== this.availabilityGeneration) return;
      this.hasAvailability = true;
      this.applyAvailability(result);
    } catch {
      // Admission remains authoritative if the optional availability probe is temporarily unreachable.
    }
  }

  private applyAvailability(availability: AgentAvailabilityResponseV2) {
    if (this.lifecycleController.signal.aborted) return;
    if (this.availabilityTimer) {
      clearTimeout(this.availabilityTimer);
      this.availabilityTimer = undefined;
    }
    if (availability.state === 'available') {
      this.emitUpdate({ kind: 'availabilityChanged', availability: { state: 'available' } });
      return;
    }
    const resetAt = availability.resetAt ? Date.parse(availability.resetAt) : undefined;
    this.emitUpdate({
      kind: 'availabilityChanged',
      availability: {
        state: 'capacity_exhausted',
        ...(resetAt ? { resetAt } : {}),
      },
    });
    if (this.lifecycleController.signal.aborted) return;
    if (!resetAt) return;
    this.availabilityTimer = setTimeout(() => {
      if (this.lifecycleController.signal.aborted) return;
      const availabilityGeneration = ++this.availabilityGeneration;
      this.availabilityTimer = undefined;
      this.emitUpdate({ kind: 'availabilityChanged', availability: { state: 'available' } });
      void this.probeAvailability(availabilityGeneration);
    }, Math.min(Math.max(0, resetAt - this.now()), MAX_TIMER_DELAY_MS));
  }

  applyLocalCapacityFailure(resetAt?: number) {
    this.availabilityGeneration += 1;
    this.applyAvailability({
      protocolVersion: 3,
      state: 'capacity_exhausted',
      ...(resetAt ? { resetAt: new Date(resetAt).toISOString() } : {}),
    });
  }

  private clearAvailability() {
    this.availabilityGeneration += 1;
    if (this.availabilityTimer) clearTimeout(this.availabilityTimer);
    this.availabilityTimer = undefined;
    this.availabilityPromise = undefined;
    this.hasAvailability = false;
    this.emitUpdate({ kind: 'availabilityChanged', availability: { state: 'available' } });
  }

  private clearUserQuota() {
    if (this.userQuotaTimer) clearTimeout(this.userQuotaTimer);
    this.userQuotaTimer = undefined;
    this.userQuotaPromise = undefined;
    this.hasUserQuota = false;
    this.emitUpdate({ kind: 'userQuotaChanged' });
  }

  private getJson<T>(url: string, decoder: (value: unknown) => T, trace?: AgentClientTrace) {
    return this.dependencies.getJson(url, decoder, { signal: this.lifecycleController.signal }, trace);
  }

  private now() {
    return this.dependencies.now();
  }

  private assertActive() {
    if (this.lifecycleController.signal.aborted) throw new Error('Agent V2 runtime is destroyed');
  }

  private emitUpdate(update: AgentV2ClientUpdate) {
    if (!this.lifecycleController.signal.aborted) this.dependencies.onUpdate(update);
  }
}
