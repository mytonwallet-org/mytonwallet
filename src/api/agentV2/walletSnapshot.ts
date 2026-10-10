import type { AgentWalletSnapshotV1 } from './protocol/types';
import type { AgentV2WalletSession } from './walletSession';

import { collectWalletContacts } from './walletQueryAccounts';
import { safeWalletQueryAccountLabel } from './walletQueryOutput';
import { collectWalletSnapshotPositions } from './walletQueryPositions';
import { canonicalWalletQueryRowId } from './walletQueryRowId';

// The snapshot is the whole request body, and the production ingress accepts bodies up to 1 MiB
export const WALLET_SNAPSHOT_UPLOAD_MAX_BYTES = 1024 * 1024;

export function projectWalletSnapshot(
  session: AgentV2WalletSession,
  instanceId: string,
  snapshotRevision: number,
  now: number,
): AgentWalletSnapshotV1 | undefined {
  const snapshot = session.snapshot();
  const { host } = snapshot;
  if (!host?.activeAccountId || !host.activeNetwork) return undefined;
  const activeAccountRef = snapshot.accountRefs.get(host.activeAccountId);
  if (!activeAccountRef) return undefined;
  const capturedAt = new Date(now).toISOString();
  const accounts = host.accounts.filter(({ state }) => state !== 'deleted');
  const contacts = collectWalletContacts(session, snapshot, accounts, {
    // eslint-disable-next-line no-null/no-null -- The query contract uses null for no filter.
    purpose: 'send_recipient_resolution', chains: [], query: null,
    // The server picks the networks of a read from every own wallet the snapshot keeps
    ownWalletChains: [...new Set(accounts.flatMap(({ chains }) => chains))],
  }, true);
  const value: AgentWalletSnapshotV1 = {
    schemaVersion: 1, instanceId, snapshotRevision,
    sessionId: snapshot.sessionId, revision: snapshot.revision,
    activeAccountRef, activeNetwork: host.activeNetwork, baseCurrency: host.baseCurrency, capturedAt,
    accounts: accounts.map((account) => {
      const accountRef = snapshot.accountRefs.get(account.accountId)!;
      const source = account.domainStates?.fungible;
      const sourceTimestamp = source?.updatedAt ? Date.parse(source.updatedAt) : NaN;
      const sourceAsOf = Number.isFinite(sourceTimestamp) && sourceTimestamp <= now
        ? new Date(sourceTimestamp).toISOString() : undefined;
      const positions = source?.state === 'fresh' && sourceAsOf
        ? collectWalletSnapshotPositions(session, snapshot, account) : undefined;
      return {
        rowId: canonicalWalletQueryRowId('account', accountRef),
        accountRef, label: safeWalletQueryAccountLabel(account),
        state: account.state as 'active' | 'stale', chains: account.chains,
        accountType: account.accountType, isViewOnly: account.isViewOnly,
        positions: {
          asOf: sourceAsOf ?? capturedAt,
          ...(sourceAsOf ? { sourceAsOf } : {}),
          // A cached balance without an observation time cannot establish source freshness
          status: !positions ? 'unavailable' : positions.invalidRows ? 'partial' : 'complete',
          items: (positions && !positions.invalidRows ? positions.candidates : []).map(({ row, visibility }) => ({
            row: { ...row, assetRef: session.getAssetRef(account.accountId, row.asset.slug, row.chain) }, visibility,
          })),
        },
      };
    }),
    contacts: {
      asOf: capturedAt,
      status: contacts.missingBindings
        || accounts.some((account) => account.domainStates?.contacts?.state !== 'fresh')
        ? 'partial' : 'complete',
      items: contacts.items,
    },
  };
  // Keep the directory complete; cache misses use the ordinary scoped wallet query
  const sections = [
    value.accounts.find(({ accountRef }) => accountRef === activeAccountRef)!.positions,
    value.contacts,
    ...value.accounts.filter(({ accountRef }) => accountRef !== activeAccountRef).map(({ positions }) => positions),
  ];
  const candidates = sections.map((section) => ({ section, items: section.items, status: section.status }));
  for (const { section, items } of candidates) {
    section.items = [];
    if (items.length) section.status = 'partial';
  }
  const byteLength = () => new TextEncoder().encode(JSON.stringify(value)).length;
  if (byteLength() > WALLET_SNAPSHOT_UPLOAD_MAX_BYTES) return undefined;
  for (const { section, items, status } of candidates) {
    if (status !== 'complete' || items.length > 10_000) continue;
    Object.assign(section, { items, status });
    if (byteLength() > WALLET_SNAPSHOT_UPLOAD_MAX_BYTES) {
      section.items = [];
      section.status = 'partial';
    }
  }
  return value;
}
