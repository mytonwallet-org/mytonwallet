import type { InstallAttributionCandidate } from '../../util/installAttribution';
import type { createStorage } from '../storages';
import type { ApiInitArgs } from '../types';

import { IS_EXTENSION } from '../../config';
import { normalizeAttributionCandidate } from '../../util/installAttribution';
import { callBackendPost } from '../common/backend';
import { getEnvironment } from '../environment';
import { getCurrentStorage } from '../storages';

type RuntimeStorage = ReturnType<typeof createStorage>;
interface AttributionState extends InstallAttributionCandidate {
  claimed?: boolean;
  legacy?: boolean;
}

export function isAllowedChannel(channel: string): boolean {
  return /^[a-z0-9_]{1,64}$/.test(channel);
}

export async function claimAttribution(
  channel: string, platform: string, referrerDomain?: string, snapshot?: InstallAttributionCandidate,
): Promise<boolean> {
  const candidate = normalizeAttributionCandidate(snapshot ?? {
    channel, attributionKind: referrerDomain ? 'referrer' : 'utm', referrerDomain,
  });
  if (!candidate) return false;
  const res = await callBackendPost<{ ok: boolean }>('/attribution/claim', { ...candidate, platform });
  return Boolean(res?.ok);
}

function candidateFromArgs(args: ApiInitArgs): InstallAttributionCandidate | undefined {
  return normalizeAttributionCandidate(args);
}

async function readState(storage: RuntimeStorage): Promise<AttributionState | undefined> {
  const state = await storage.getItem('installAttribution') as AttributionState | undefined;
  if (state) {
    const candidate = candidateFromArgs(state);
    return candidate ? { ...candidate, claimed: state.claimed === true } : undefined;
  }
  const channel = await storage.getItem('attributionChannel');
  if (!channel || !isAllowedChannel(channel)) return undefined;
  // Legacy channels were explicit/native. Never relabel them as overridable referrers.
  return {
    channel, attributionKind: 'utm', claimed: Boolean(await storage.getItem('attributionClaimed')), legacy: true,
  };
}

// Serialize storage transitions, but never hold this queue over a network request. A later explicit
// source can replace a referrer while its POST is in flight; that response acknowledges its own value.
let transitions: Promise<unknown> = Promise.resolve();
function transition<T>(action: () => Promise<T>): Promise<T> {
  const result = transitions.then(action, action);
  transitions = result.catch(() => {});
  return result;
}
const draining = new WeakSet<RuntimeStorage>();

function sameCandidate(a: AttributionState | undefined, b: AttributionState) {
  return a?.channel === b.channel && a.attributionKind === b.attributionKind && a.referrerDomain === b.referrerDomain
    && a.utmMedium === b.utmMedium && a.utmCampaign === b.utmCampaign && a.utmContent === b.utmContent;
}

export async function claimInstallAttribution(args: ApiInitArgs, storage: RuntimeStorage) {
  try {
    await persistAttribution(args, storage);
    if (draining.has(storage)) return;
    draining.add(storage);
    try {
      while (true) {
        const selected = await transition(() => readState(storage));
        if (!selected || selected.claimed) return;
        const env = getEnvironment();
        const platform = env.isIosApp ? 'ios' : env.isAndroidApp ? 'android'
          : IS_EXTENSION ? 'extension' : env.isElectron ? 'electron' : 'web';
        let ok = false;
        try {
          ok = selected.legacy
            ? Boolean((await callBackendPost<{ ok: boolean }>('/attribution/claim', {
              channel: selected.channel, platform,
            }))?.ok)
            : await claimAttribution(selected.channel, platform, selected.referrerDomain, selected);
        } catch { /* Retain the pending candidate for the next init. */ }
        const changed = await transition(async () => {
          const current = await readState(storage);
          if (!sameCandidate(current, selected)) return true;
          if (ok) {
            if (selected.legacy) await storage.setItem('attributionClaimed', '1');
            else await storage.setItem('installAttribution', { ...selected, claimed: true });
          }
          return false;
        });
        if (!changed) return;
      }
    } finally {
      draining.delete(storage);
    }
  } catch { /* Storage/network failure must not reject into SDK startup. */ }
}

export async function setInstallChannel(
  channel: string, storage: RuntimeStorage, referrerDomain?: string, technicalKind?: 'referral',
) {
  if (technicalKind === 'referral' || (!referrerDomain && ['organic', 'unknown'].includes(channel))) {
    try {
      if (await storage.getItem('attributionTechnicalClaimed')) return;
      const res = await callBackendPost<{ ok: boolean }>('/attribution/claim', {
        channel: '', platform: 'android', attributionKind: technicalKind ?? 'direct',
      });
      if (res?.ok) await storage.setItem('attributionTechnicalClaimed', '1');
    } catch { /* Retry technical status on the next Play referrer delivery. */ }
    return;
  }
  await claimInstallAttribution({
    channel, ...(referrerDomain && { attributionKind: 'referrer', referrerDomain }),
  }, storage);
}

async function persistAttribution(args: ApiInitArgs, storage: RuntimeStorage) {
  await transition(async () => {
    const saved = await readState(storage);
    const candidate = candidateFromArgs(args);
    if (candidate && (!saved || (saved.attributionKind === 'referrer' && candidate.attributionKind === 'utm'))) {
      await storage.setItem('installAttribution', candidate);
    }
  });
}

// Native callers may discard their durable pending value only after SDK storage accepts it.
export async function acceptInstallAttribution(snapshot: InstallAttributionCandidate, storage: RuntimeStorage) {
  if (!normalizeAttributionCandidate(snapshot)) throw new Error('Invalid attribution source');
  await persistAttribution(snapshot, storage);
  void claimInstallAttribution({}, storage);
  return true;
}

export async function captureInstallAttribution(snapshot: InstallAttributionCandidate) {
  return acceptInstallAttribution(snapshot, getCurrentStorage());
}
