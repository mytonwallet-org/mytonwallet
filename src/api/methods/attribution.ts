import type { InstallAttributionCandidate } from '../../util/installAttribution';
import type { createStorage } from '../storages';
import type { ApiInitArgs } from '../types';

import { IS_EXTENSION } from '../../config';
import { mergeAbortSignalsWithTimeout, raceWithAbortSignal } from '../../util/abortSignal';
import { normalizeAttributionCandidate } from '../../util/installAttribution';
import { callWindow } from '../../util/windowProvider/connector';
import { callBackendPost } from '../common/backend';
import { getEnvironment } from '../environment';
import { getCurrentStorage } from '../storages';

type RuntimeStorage = ReturnType<typeof createStorage>;
type TechnicalKind = 'direct' | 'referral';
interface AttributionState extends InstallAttributionCandidate {
  claimed?: boolean;
  legacy?: boolean;
}
interface PlayInstallOutcome {
  sourceOutcome: string;
  playInstalledAt?: number | null;
}

const PLAY_OUTCOME_KINDS: Record<string, TechnicalKind> = {
  organic: 'direct',
  empty_referrer: 'direct',
  missing_source: 'direct',
  invalid_source: 'direct',
  play_unavailable: 'direct',
  not_play_install: 'direct',
  stale_referrer: 'direct',
  referral: 'referral',
};
// Stale or failed Play answers say nothing about the install: they never refine a claim or block one that does
const UNINFORMATIVE_OUTCOMES = new Set(['stale_referrer', 'play_unavailable']);

export function isAllowedChannel(channel: string): boolean {
  return /^[a-z0-9_]{1,64}$/.test(channel);
}

function candidateFromArgs(args: ApiInitArgs): InstallAttributionCandidate | undefined {
  return normalizeAttributionCandidate(args);
}

async function readState(storage: RuntimeStorage): Promise<AttributionState | undefined> {
  const state = await storage.getItem('installAttribution') as AttributionState | undefined;
  if (state) {
    const candidate = selectWalletCandidate(state);
    return candidate ? { ...candidate, claimed: state.claimed === true } : undefined;
  }
  const channel = await storage.getItem('attributionChannel');
  if (!channel || !isAllowedChannel(channel)) return undefined;
  // Legacy channels were explicit/native. Never relabel them as overridable referrers.
  return {
    channel, attributionKind: 'utm', claimed: Boolean(await storage.getItem('attributionClaimed')), legacy: true,
  };
}

function selectWalletCandidate(value: AttributionState): AttributionState | undefined {
  if (value.legacy === true) {
    return value.attributionKind === 'utm' && isAllowedChannel(value.channel)
      ? { channel: value.channel, attributionKind: 'utm', legacy: true } : undefined;
  }
  return normalizeAttributionCandidate(value);
}

// Serialize storage transitions, but never hold this queue over a network request. A later explicit
// source can replace a referrer while its POST is in flight; that response acknowledges its own value.
let transitions: Promise<unknown> = Promise.resolve();
function transition<T>(action: () => Promise<T>): Promise<T> {
  const result = transitions.then(action, action);
  transitions = result.catch(() => {});
  return result;
}
const draining = new WeakMap<RuntimeStorage, () => boolean>();

function sameCandidate(a: AttributionState | undefined, b: AttributionState) {
  return a?.channel === b.channel && a.attributionKind === b.attributionKind && a.referrerDomain === b.referrerDomain
    && a.utmMedium === b.utmMedium && a.utmCampaign === b.utmCampaign && a.utmContent === b.utmContent
    && a.legacy === b.legacy;
}

export async function claimInstallAttribution(
  args: ApiInitArgs, storage: RuntimeStorage, isAlive?: () => boolean, installationId?: string,
) {
  const owns = isAlive ?? (() => true);
  try {
    await persistAttribution(args, storage, owns);
    if (!owns() || draining.get(storage)?.()) return;
    draining.set(storage, owns);
    try {
      while (true) {
        const selected = await transition(() => readState(storage));
        if (!owns() || !selected || selected.claimed) return;
        const env = getEnvironment();
        const platform = env.isIosApp ? 'ios' : env.isAndroidApp ? 'android'
          : IS_EXTENSION ? 'extension' : env.isElectron ? 'electron' : 'web';
        let ok = false;
        try {
          const candidate = selected.legacy ? { channel: selected.channel } : normalizeAttributionCandidate(selected);
          const payload = candidate && { ...candidate, platform, ...(installationId && { installationId }) };
          ok = payload ? Boolean((await postWalletClaim(payload, isAlive))?.ok) : false;
        } catch { /* Retain the pending candidate for the next init. */ }
        const changed = await transition(async () => {
          const current = await readState(storage);
          if (!owns()) return false;
          if (!sameCandidate(current, selected)) return true;
          if (ok) {
            if (selected.legacy && !await storage.getItem('installAttribution')) {
              if (owns()) await storage.setItem('attributionClaimed', '1');
            } else if (owns()) await storage.setItem('installAttribution', { ...selected, claimed: true });
          }
          return false;
        });
        if (!changed) return;
      }
    } finally {
      if (draining.get(storage) === owns) draining.delete(storage);
    }
  } catch { /* Storage/network failure must not reject into SDK startup. */ }
}

function selectOutcomeFields(attributionKind: TechnicalKind, outcome?: PlayInstallOutcome) {
  if (!outcome || PLAY_OUTCOME_KINDS[outcome.sourceOutcome] !== attributionKind) return undefined;
  const { sourceOutcome, playInstalledAt } = outcome;
  return { sourceOutcome, ...(Number.isSafeInteger(playInstalledAt) && { playInstalledAt }) };
}

async function readTechnicalClaim(
  storage: RuntimeStorage, attributionKind: TechnicalKind, outcome?: PlayInstallOutcome,
) {
  const fields = selectOutcomeFields(attributionKind, outcome);
  const isClaimed = Boolean(await storage.getItem('attributionTechnicalClaimed'));
  const isOutcomeDue = isClaimed && fields !== undefined && !UNINFORMATIVE_OUTCOMES.has(fields.sourceOutcome)
    && !await storage.getItem('attributionOutcomeClaimed');
  return { fields, isClaimed, isDue: !isClaimed || isOutcomeDue };
}

export async function setInstallChannel(
  channel: string, storage: RuntimeStorage, referrerDomain?: string, technicalKind?: 'referral',
  isAlive?: () => boolean, outcome?: PlayInstallOutcome, installationId?: string,
) {
  const owns = isAlive ?? (() => true);
  if (technicalKind === 'referral' || (!referrerDomain && ['organic', 'unknown'].includes(channel))) {
    const attributionKind = technicalKind ?? 'direct';
    try {
      const { fields, isClaimed, isDue } = await readTechnicalClaim(storage, attributionKind, outcome);
      if (!isDue || !owns()) return;
      const res = await postWalletClaim({
        channel: '', platform: 'android', attributionKind, ...fields, ...(installationId && { installationId }),
      }, isAlive);
      if (!res?.ok || !owns()) return;
      if (!isClaimed) await storage.setItem('attributionTechnicalClaimed', '1');
      if (fields && !UNINFORMATIVE_OUTCOMES.has(fields.sourceOutcome)) {
        await storage.setItem('attributionOutcomeClaimed', '1');
      }
    } catch { /* Retry technical status on the next Play referrer delivery. */ }
    return;
  }
  await claimInstallAttribution({
    channel, ...(referrerDomain && { attributionKind: 'referrer', referrerDomain }),
  }, storage, isAlive, installationId);
}

async function postWalletClaim(payload: AnyLiteral, isAlive?: () => boolean): Promise<{ ok: boolean }> {
  if (!isAlive) return callBackendPost('/attribution/claim', payload);
  if (!isAlive()) return { ok: false };
  const controller = new AbortController();
  const { signal, cleanup } = mergeAbortSignalsWithTimeout(30000, controller.signal);
  try {
    return await raceWithAbortSignal(() => callBackendPost<{ ok: boolean }>(
      '/attribution/claim', payload, { signal },
    ), signal);
  } finally {
    controller.abort();
    cleanup();
  }
}

async function persistAttribution(args: ApiInitArgs, storage: RuntimeStorage, isAlive: () => boolean = () => true) {
  await transition(async () => {
    const saved = await readState(storage);
    const candidate = candidateFromArgs(args);
    if (isAlive() && candidate
      && (!saved || (saved.attributionKind === 'referrer' && candidate.attributionKind === 'utm'))) {
      await storage.setItem('installAttribution', candidate);
    }
  });
}

export async function syncAndroidWalletAttribution(storage: RuntimeStorage, isAlive: () => boolean): Promise<boolean> {
  try {
    const saved = await transition(() => readState(storage));
    if (!isAlive()) return false;
    const seed = saved && selectWalletCandidate(saved);
    const {
      source, technicalKind, sourceOutcome, playInstalledAt, installationId: nativeInstallationId,
    } = await callWindow('airInstallationSyncWalletAttribution', seed ? JSON.stringify(seed) : 'null');
    const outcome = sourceOutcome ? { sourceOutcome, playInstalledAt } : undefined;
    const installationId = typeof nativeInstallationId === 'string' ? nativeInstallationId : undefined;
    if (!isAlive()) return false;
    if (source) {
      const selected = selectWalletCandidate(source);
      if (!selected) throw new Error('Invalid wallet attribution source');
      await transition(async () => {
        const current = await readState(storage);
        if (isAlive() && !sameCandidate(current, selected)) {
          await storage.setItem('installAttribution', selected);
        }
      });
      await claimInstallAttribution({}, storage, isAlive, installationId);
    }
    const kind = technicalKind === 'referral' ? 'referral' : undefined;
    if (technicalKind) {
      await setInstallChannel('organic', storage, undefined, kind, isAlive, outcome, installationId);
    }
    const current = await readState(storage);
    const isTechnicalClaimed = !technicalKind
      || !(await readTechnicalClaim(storage, kind ?? 'direct', outcome)).isDue;
    return isAlive() && (!source || current?.claimed === true) && isTechnicalClaimed;
  } catch {
    return false;
  }
}

// Native callers may discard their durable pending value only after SDK storage accepts it.
export async function acceptInstallAttribution(snapshot: InstallAttributionCandidate, storage: RuntimeStorage) {
  if (!normalizeAttributionCandidate(snapshot)) throw new Error('Invalid attribution source');
  await persistAttribution(snapshot, storage);
  // An Android claim must carry the installation id, and only the native wallet sync supplies it
  if (!getEnvironment().isAndroidApp) void claimInstallAttribution({}, storage);
  return true;
}

export async function captureInstallAttribution(snapshot: InstallAttributionCandidate) {
  return acceptInstallAttribution(snapshot, getCurrentStorage());
}
