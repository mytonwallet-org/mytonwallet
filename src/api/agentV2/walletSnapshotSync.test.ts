import type { AgentWalletSnapshotAckV1, AgentWalletSnapshotV1 } from './protocol/types';
import type { AgentV2HostContextSnapshot } from './types';

import { getSupportedChains } from '../../util/chain';
import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { AgentV2HttpError } from './identity';
import { AgentV2WalletSession } from './walletSession';
import { projectWalletSnapshot, WALLET_SNAPSHOT_UPLOAD_MAX_BYTES } from './walletSnapshot';
import { AgentV2WalletSnapshotSync } from './walletSnapshotSync';

const INSTANCE = '11111111-1111-4111-8111-111111111111';
const NOW = Date.parse('2026-09-21T12:00:00.000Z');
const CHAIN_CASES = [
  { name: 'runtime catalog', chains: [...getSupportedChains()] },
  { name: '65 future chains', chains: Array.from({ length: 65 }, (_, index) => `future-chain-${index}`) },
];

function host(): AgentV2HostContextSnapshot {
  return {
    platform: 'classic', uiCapabilities: hostUiCapabilities('classic'), client: 'web', lang: 'en',
    baseCurrency: 'USD', currencyRate: '1', activeAccountId: 'main', activeNetwork: 'ton', isTestnet: false,
    accounts: [{
      accountId: 'main', label: 'Main', state: 'active', accountType: 'regular', isViewOnly: false,
      chains: ['ton'], addresses: { ton: 'EQ-own-public-address' },
      holdings: [{ asset: { slug: 'toncoin', chain: 'ton', symbol: 'TON', decimals: 9 },
        balance: '10', availableBalance: '9', valuationStatus: 'valued', fiatValue: '30', visibility: 'hidden' }],
      savedAddresses: [{ id: 'mum', name: 'Mum', chain: 'ton', address: 'EQ-contact-public-address' }],
      domainStates: {
        fungible: { state: 'fresh', updatedAt: new Date(NOW).toISOString() }, contacts: { state: 'fresh' },
      },
    }], savedAddresses: [],
  };
}

function fixture() {
  const session = new AgentV2WalletSession();
  session.update(host());
  let now = NOW;
  const sends: {
    value: AgentWalletSnapshotV1;
    signal: AbortSignal;
    resolve: (value: AgentWalletSnapshotAckV1) => void;
    reject: (error: unknown) => void;
  }[] = [];
  const sync = new AgentV2WalletSnapshotSync({ session, now: () => now, instanceId: INSTANCE,
    send: (value, signal) => new Promise((resolve, reject) => {
      sends.push({ value, signal, resolve, reject });
    }),
  });
  return { session, sync, sends, advance: (ms: number) => {
    now += ms;
  } };
}

function acknowledge(entry: ReturnType<typeof fixture>['sends'][number]) {
  const { instanceId, sessionId, revision, snapshotRevision } = entry.value;
  entry.resolve({ snapshotRef: { instanceId, sessionId, revision, snapshotRevision } });
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

describe('wallet snapshot synchronization', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
  });

  it('projects existing rows and references without public wallet or contact addresses', () => {
    const { session } = fixture();
    const snapshot = projectWalletSnapshot(session, INSTANCE, 1, NOW)!;
    expect(snapshot.activeNetwork).toBe('ton');
    expect(snapshot.accounts[0].positions).toMatchObject({ status: 'complete', items: [{ visibility: 'hidden', row: {
      quantity: '10', availableQuantity: '9', fiatValue: '30',
    } }] });
    expect(snapshot.contacts.items.map(({ source }) => source)).toEqual(['saved', 'own_wallet']);
    expect(JSON.stringify(snapshot)).not.toContain('EQ-own-public-address');
    expect(JSON.stringify(snapshot)).not.toContain('EQ-contact-public-address');
    expect(session.resolveSavedAddressRefs('main', 'mum')).toEqual({
      addressRef: snapshot.contacts.items[0].row.addressRef, contactRef: snapshot.contacts.items[0].row.contactRef,
    });
  });

  it('leaves runs independent of a slow upload and uses only its exact acknowledged reference', async () => {
    const { sync, sends } = fixture();
    expect(sends).toHaveLength(0);
    sync.setActive(true);
    expect(sync.forRun()).toEqual({});
    acknowledge(sends[0]);
    await flush();
    expect(sync.forRun()).toEqual({ walletSnapshotRef: {
      instanceId: INSTANCE, sessionId: sends[0].value.sessionId,
      revision: sends[0].value.revision, snapshotRevision: 1,
    } });
    expect(sends).toHaveLength(1);
  });

  it.each(CHAIN_CASES)('uploads every $name chain and binds runs to the acknowledged snapshot', async ({ chains }) => {
    const { session, sync, sends } = fixture();
    const updated = host();
    updated.activeNetwork = chains[0];
    updated.accounts[0].chains = [...chains];
    updated.accounts[0].addresses = Object.fromEntries(chains.map((chain) => [chain, `address-main-${chain}`]));
    updated.accounts[0].holdings = [];
    updated.accounts[0].savedAddresses = [];
    session.update(updated);

    const projected = projectWalletSnapshot(session, INSTANCE, 1, NOW)!;
    expect(projected.accounts[0].chains).toEqual(chains);
    expect(new TextEncoder().encode(JSON.stringify(projected)).length)
      .toBeLessThanOrEqual(WALLET_SNAPSHOT_UPLOAD_MAX_BYTES);
    sync.setActive(true);
    expect(sends).toHaveLength(1);
    expect(sends[0].value.accounts[0].chains).toEqual(chains);
    expect(new TextEncoder().encode(JSON.stringify(sends[0].value)).length)
      .toBeLessThanOrEqual(WALLET_SNAPSHOT_UPLOAD_MAX_BYTES);
    expect(sync.forRun()).toEqual({});

    const { instanceId, sessionId, revision, snapshotRevision } = sends[0].value;
    acknowledge(sends[0]);
    await flush();
    expect(sync.forRun()).toEqual({ walletSnapshotRef: { instanceId, sessionId, revision, snapshotRevision } });
    expect(sends).toHaveLength(1);
    sync.setActive(false);
  });

  it('coalesces pending updates and preserves wallet revision across balance updates', async () => {
    const { sync, session, sends } = fixture();
    sync.setActive(true);
    const first = sends[0].value;
    for (const balance of ['11', '12']) {
      const updated = host();
      updated.accounts[0].holdings[0].balance = balance;
      session.update(updated);
      sync.refresh();
    }
    expect(sends).toHaveLength(1);
    expect(sync.forRun()).toEqual({});
    acknowledge(sends[0]);
    await flush();
    expect(sends).toHaveLength(2);
    expect(sends[1].value.snapshotRevision).toBe(3);
    expect(sends[1].value.revision).toBe(first.revision);
    expect(sends[1].value.accounts[0].positions.items[0].row.quantity).toBe('12');
    acknowledge(sends[1]);
    await flush();
    sync.setActive(false);
  });

  it('preserves unchanged section timestamps within the revalidation interval', async () => {
    const { sync, session, sends, advance } = fixture();
    sync.setActive(true);
    const first = sends[0].value;
    acknowledge(sends[0]);
    await flush();
    advance(1_000);
    sync.refresh();
    expect(sends).toHaveLength(1);
    const updated = host();
    updated.accounts[0].savedAddresses![0].name = 'Mother';
    session.update(updated);
    sync.refresh();
    const second = sends[1].value;
    expect(second.accounts[0].positions.asOf).toBe(first.accounts[0].positions.asOf);
    expect(second.contacts.asOf).not.toBe(first.contacts.asOf);
  });

  it('renews unchanged local data while the chat stays open', async () => {
    const { sync, sends, advance } = fixture();
    sync.setActive(true);
    const first = sends[0].value;
    acknowledge(sends[0]);
    await flush();

    advance(25_000);
    jest.advanceTimersByTime(25_000);
    expect(sends).toHaveLength(2);
    const renewed = sends[1].value;
    expect(renewed.snapshotRevision).toBeGreaterThan(first.snapshotRevision);
    expect(renewed.revision).toBe(first.revision);
    expect(renewed.contacts.asOf).toBe(new Date(NOW + 25_000).toISOString());
    expect(renewed.accounts[0].positions.asOf).toBe(first.accounts[0].positions.asOf);
    expect(renewed.accounts[0].positions.items).toEqual(first.accounts[0].positions.items);
    expect(sync.forRun()).toEqual({});
    acknowledge(sends[1]);
    await flush();
    expect(sync.forRun().walletSnapshotRef?.snapshotRevision).toBe(renewed.snapshotRevision);

    sync.setActive(false);
    advance(60_000);
    jest.advanceTimersByTime(60_000);
    expect(sends).toHaveLength(2);
  });

  it('renews an expired reference before a run even when background timers did not fire', async () => {
    const { sync, sends, advance } = fixture();
    sync.setActive(true);
    acknowledge(sends[0]);
    await flush();
    advance(31 * 60_000);

    const result = sync.forRun();
    expect(result.walletSnapshotRef).toBeUndefined();
    expect(sends[1].value.snapshotRevision).toBeGreaterThan(sends[0].value.snapshotRevision);
    expect(sends[1].value.capturedAt).toBe(new Date(NOW + 31 * 60_000).toISOString());
  });

  it('revalidates contacts even while balance updates keep publishing snapshots', async () => {
    const { sync, session, sends, advance } = fixture();
    sync.setActive(true);
    acknowledge(sends[0]);
    await flush();

    advance(15_000);
    jest.advanceTimersByTime(15_000);
    const updated = host();
    updated.accounts[0].holdings[0].balance = '11';
    session.update(updated);
    sync.refresh();
    expect(sends).toHaveLength(2);
    expect(sends[1].value.contacts.asOf).toBe(sends[0].value.contacts.asOf);
    acknowledge(sends[1]);
    await flush();

    advance(10_000);
    jest.advanceTimersByTime(10_000);
    expect(sends).toHaveLength(3);
    expect(sends[2].value.contacts.asOf).toBe(new Date(NOW + 25_000).toISOString());
    expect(sends[2].value.accounts[0].positions.items[0].row.quantity).toBe('11');
  });

  it('preserves source age when revalidating timestamped holdings', async () => {
    const { sync, session, sends, advance } = fixture();
    const updated = host();
    updated.accounts[0].domainStates!.fungible!.updatedAt = new Date(NOW - 60_000).toISOString();
    session.update(updated);
    sync.setActive(true);
    const first = sends[0].value;
    acknowledge(sends[0]);
    await flush();
    advance(25_000);
    sync.refresh();
    const renewed = sends[1].value;

    expect(renewed.snapshotRevision).toBeGreaterThan(first.snapshotRevision);
    expect(renewed.accounts[0].positions.asOf).toBe(first.accounts[0].positions.asOf);
    expect(renewed.accounts[0].positions.sourceAsOf).toBe(first.accounts[0].positions.sourceAsOf);
    expect(renewed.contacts.asOf).toBe(renewed.capturedAt);
  });

  it.each([undefined, 'invalid', new Date(NOW + 60_000).toISOString()])(
    'does not upload balances without a usable source timestamp: %s', (updatedAt) => {
      const { session } = fixture();
      const updated = host();
      updated.accounts[0].domainStates!.fungible!.updatedAt = updatedAt;
      session.update(updated);
      const first = projectWalletSnapshot(session, INSTANCE, 1, NOW)!;
      expect(first.accounts[0].positions).toMatchObject({ status: 'unavailable', items: [] });
      const renewed = projectWalletSnapshot(session, INSTANCE, 2, NOW + 25_000)!;
      expect(renewed.accounts[0].positions.status).toBe('unavailable');
      expect(renewed.accounts[0].positions.sourceAsOf).toBeUndefined();
      expect(renewed.contacts.status).toBe('complete');
    },
  );

  it('updates balance freshness when the host supplies a new source timestamp for equal balances', async () => {
    const { sync, session, sends, advance } = fixture();
    sync.setActive(true);
    const first = sends[0].value;
    acknowledge(sends[0]);
    await flush();
    advance(10_000);
    const updated = host();
    updated.accounts[0].domainStates!.fungible!.updatedAt = new Date(NOW + 10_000).toISOString();
    session.update(updated);
    sync.refresh();
    const renewed = sends[1].value;

    expect(renewed.snapshotRevision).toBeGreaterThan(first.snapshotRevision);
    expect(renewed.accounts[0].positions).toMatchObject({
      status: 'complete', asOf: new Date(NOW + 10_000).toISOString(),
      sourceAsOf: new Date(NOW + 10_000).toISOString(), items: first.accounts[0].positions.items,
    });
  });

  it('does not retry a rejected payload on refresh or timestamp-only renewal, but sends changed data', async () => {
    const { sync, session, sends, advance } = fixture();
    sync.setActive(true);
    sends[0].reject(new AgentV2HttpError(413, 'invalid_request', 'Too large', false));
    await flush();
    expect(sync.forRun()).toEqual({});
    advance(25_000);
    jest.advanceTimersByTime(25_000);
    expect(sync.forRun()).toEqual({});
    expect(sends).toHaveLength(1);

    const updated = host();
    updated.accounts[0].holdings[0].balance = '11';
    session.update(updated);
    sync.refresh();
    expect(sends).toHaveLength(2);
    acknowledge(sends[1]);
    await flush();
    expect(sync.forRun().walletSnapshotRef?.snapshotRevision).toBe(sends[1].value.snapshotRevision);
  });

  it('retries a transient upload without duplicating it during a run', async () => {
    const { sync, sends } = fixture();
    sync.setActive(true);
    expect(sync.forRun()).toEqual({});
    sends[0].reject(new TypeError('offline'));
    await flush();
    await jest.advanceTimersByTimeAsync(250);
    expect(sends).toHaveLength(2);
    expect(sends[1].value).toBe(sends[0].value);
    acknowledge(sends[1]);
    await flush();
    expect(sync.forRun().walletSnapshotRef).toBeDefined();
    expect(sends).toHaveLength(2);
  });

  it('aborts background work on close and ignores late acknowledgements after reset', async () => {
    const { sync, sends } = fixture();
    sync.setActive(true);
    sync.setActive(false);
    expect(sends[0].signal.aborted).toBe(true);
    sync.reset();
    acknowledge(sends[0]);
    await flush();
    expect(sync.forRun().walletSnapshotRef).toBeUndefined();
    sync.setActive(true);
    expect(sends).toHaveLength(2);
    sync.setActive(false);
    acknowledge(sends[1]);
    await flush();
  });

  it('bounds rich Unicode snapshots while retaining the directory, active account and whole sections', () => {
    const { session } = fixture();
    const updated = host();
    updated.accounts = Array.from({ length: 20 }, (_, i) => ({
      ...updated.accounts[0], accountId: `wallet-${i}`, label: `Кошелёк ${i}`, savedAddresses: [],
      holdings: Array.from({ length: 120 }, (_, j) => ({
        ...updated.accounts[0].holdings[0], asset: { ...updated.accounts[0].holdings[0].asset, slug: `asset-${j}` },
      })),
    }));
    updated.activeAccountId = 'wallet-19';
    session.update(updated);
    const snapshot = projectWalletSnapshot(session, INSTANCE, 1, NOW)!;
    expect(WALLET_SNAPSHOT_UPLOAD_MAX_BYTES).toBe(1024 * 1024);
    expect(new TextEncoder().encode(JSON.stringify(snapshot)).length).toBeLessThanOrEqual(1024 * 1024);
    expect(snapshot.accounts.map(({ label }) => label)).toEqual(updated.accounts.map(({ label }) => label));
    expect(snapshot.accounts.at(-1)!.positions.status).toBe('complete');
    expect(snapshot.accounts.at(-1)!.positions.items).toHaveLength(120);
    expect(snapshot.contacts.status).toBe('complete');
    expect(snapshot.accounts.some(({ positions }) => positions.status === 'partial')).toBe(true);
    for (const { positions } of snapshot.accounts) {
      expect(positions.items).toHaveLength(positions.status === 'complete' ? 120 : 0);
    }
  });
});
