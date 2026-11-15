import { address, encodeReference, decodeReference, network, timestamp } from './protocol.js';
import type { Context, TradeAction } from './review.js';
import type { ReviewedIntent } from './intent.js';
export type PendingTrade = Readonly<{ version: 1; intentId: string; account: string; chain: '-239' | '-3';
  reference: string; action: TradeAction; createdAt: number; updatedAt: number;
  state: 'uncertain' | 'submitted' | 'settled' | 'failed'; messageHash: string | null;
  reservationId?: string | null }>;
/** Process-local right to release only a definitely unhanded claim. Never reconstructed from disk. */
export type PendingReservation = Readonly<{
  cancelBeforeHandoff: () => Promise<boolean>;
  capture: (guard: () => void, execute: () => undefined) => undefined;
}>;
export interface JournalStore {
  read?(): Promise<readonly PendingTrade[]>;
  /** Callback must run once under an atomic read/write transaction, including across tabs. */
  transact<T>(update: (records: readonly PendingTrade[]) => { records: readonly PendingTrade[]; result: T }): Promise<T>;
}
const actions = ['list','buy','cancel-sale','make-offer','accept-offer','cancel-offer'];
const saleActions = ['list','buy','cancel-sale'];
const capacity = 100;
const isPending = (state: PendingTrade['state']) => state === 'uncertain' || state === 'submitted';
const hex = (value: unknown, size: number) =>
  typeof value === 'string' && value.length === size && /^[a-f0-9]+$/.test(value);

function validate(row: PendingTrade): PendingTrade {
  if (!row || typeof row !== 'object' || row.version !== 1 || !hex(row.intentId,64) || !actions.includes(row.action)
    || !['uncertain','submitted','settled','failed'].includes(row.state)
    || (row.messageHash !== null && !hex(row.messageHash,64))
    || (row.reservationId != null && !hex(row.reservationId,32))) throw Error('Invalid pending journal');
  const account = address(row.account), chain = network(row.chain), reference = decodeReference(row.reference,chain);
  if (account.length !== 66 || encodeReference(reference) !== row.reference
    || reference.kind !== (saleActions.includes(row.action) ? 'sale' : 'offer')) throw Error('Invalid journal reference');
  timestamp(row.createdAt); timestamp(row.updatedAt);
  if (row.updatedAt < row.createdAt || (row.state !== 'uncertain' && row.messageHash === null)) throw Error('Invalid journal lifecycle');
  // Whitelist fields. Never persist payloads, signatures, mnemonic, API tokens or metadata.
  return Object.freeze({ version: 1, intentId: row.intentId, account: row.account, chain: row.chain,
    reference: row.reference, action: row.action, createdAt: row.createdAt, updatedAt: row.updatedAt,
    state: row.state, messageHash: row.messageHash, reservationId: row.reservationId ?? null });
}

function validateRecords(records: unknown): PendingTrade[] {
  if (!Array.isArray(records) || records.length > capacity) throw Error('Invalid journal');
  const intents = new Set<string>();
  const unresolved = new Set<string>();
  const clean: PendingTrade[] = [];
  for (const raw of records) {
    const row = validate(raw);
    if (intents.has(row.intentId)) throw Error('Duplicate journal intent');
    intents.add(row.intentId);
    if (isPending(row.state)) {
      const { nft } = decodeReference(row.reference,row.chain);
      const key = `${row.chain}|${row.account}|${nft}`;
      if (unresolved.has(key)) throw Error('Conflicting unresolved journal operations');
      unresolved.add(key);
    }
    clean.push(row);
  }
  return clean;
}

export class PendingJournal {
  constructor(private readonly store: JournalStore) {}
  private readonly listeners = new Set<() => void>();
  /** Data-free, process-local invalidation. Subscribers must read their own account scope. */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }
  private async mutate<T>(update: (records: readonly PendingTrade[]) => { records: readonly PendingTrade[]; result: T }): Promise<T> {
    try {
      return await this.store.transact(records => {
        const change = update(validateRecords(records));
        return { records: validateRecords(change.records), result: change.result };
      });
    }
    finally {
      // A failed reply may still follow a committed write. Never report a known-empty journal.
      // Observers must not turn a successful reservation into a lost capability.
      for (const listener of [...this.listeners]) { try { listener(); } catch { /* isolated observer */ } }
    }
  }
  async prepare(intent: ReviewedIntent, now: number): Promise<PendingReservation> {
    const original = await this.reserve(intent, now);
    let phase: 'ready' | 'checking' | 'handed-off' | 'closed' = 'ready';
    return Object.freeze({
      cancelBeforeHandoff: async () => {
        if (phase !== 'ready' && phase !== 'checking') return false;
        phase = 'closed'; // Also consumed if storage fails or its commit response is lost.
        await this.mutate<void>(records => {
          const matching = records.filter(r => r.intentId === original.intentId);
          if (matching.length !== 1 || JSON.stringify(matching[0]) !== JSON.stringify(original)) {
            throw Error('Reservation changed; reconcile instead of deleting');
          }
          return { records: records.filter(r => r.intentId !== original.intentId), result: undefined };
        });
        return true;
      },
      capture: (guard: () => void, execute: () => undefined) => {
        if (phase !== 'ready') throw Error('Reservation already consumed');
        phase = 'checking';
        const result: unknown = guard();
        if (result !== undefined) throw Error('Handoff guard must be synchronous');
        // A synchronous guard may reenter cancellation. Do not cross that cancellation.
        if ((phase as string) !== 'checking') throw Error('Reservation cancelled during recheck');
        phase = 'handed-off';
        return execute(); // A thrown executor error cannot release an uncertain operation.
      },
    });
  }
  async reserve(intent: ReviewedIntent, now: number): Promise<PendingTrade> {
    timestamp(now);
    const row = validate({ version: 1, intentId: intent.id, account: intent.plan.account, chain: intent.plan.chain,
      reference: encodeReference(intent.review.reference), action: intent.review.action, createdAt: now, updatedAt: now,
      state: 'uncertain', messageHash: null,
      reservationId: Array.from(crypto.getRandomValues(new Uint8Array(16)), n => n.toString(16).padStart(2,'0')).join('') });
    if (intent.review.context.account !== row.account || intent.review.context.chain !== row.chain
      || intent.review.expiresAt <= now || intent.plan.expiresAt <= now) throw Error('Stale journal reservation');
    return this.mutate<PendingTrade>(records => {
      if (records.some(r => r.intentId === row.intentId || (r.account === row.account && r.chain === row.chain
        && decodeReference(r.reference,r.chain).nft === intent.review.reference.nft
        && isPending(r.state)))) throw Error('Reconcile the previous operation first');
      // Bounded terminal history must not exhaust pending capacity after 100 successful trades.
      // Never evict an unresolved operation, including one belonging to another account/network.
      // This journal is not a permanent replay database; chain/intent verification remains mandatory.
      const clean = [...records];
      while (clean.length >= capacity) {
        const terminal = clean.findIndex(r => !isPending(r.state));
        if (terminal < 0) throw Error('Pending journal capacity reached');
        clean.splice(terminal,1);
      }
      return { records: [...clean,row], result: row };
    });
  }
  async list(context: Context): Promise<readonly PendingTrade[]> {
    address(context.account); network(context.chain);
    const records = this.store.read ? validateRecords(await this.store.read())
      : await this.store.transact(records => ({ records, result: validateRecords(records) }));
    return Object.freeze(records.filter(r => r.account === context.account && r.chain === context.chain));
  }
  /** Only independently verified receipt reconciliation may call this. No expiry-based failure. */
  async reconcile(context: Context, id: string, next: 'submitted' | 'settled' | 'failed', messageHash: string, now: number): Promise<void> {
    address(context.account); network(context.chain); timestamp(now);
    if (!['submitted','settled','failed'].includes(next) || !hex(messageHash,64)) throw Error('Journal transition rejected');
    return this.mutate<void>(records => {
      let found = false;
      const updated = records.map(r => {
        if (r.intentId !== id || r.account !== context.account || r.chain !== context.chain) return r;
        found = true;
        if (!isPending(r.state) || now < r.updatedAt
          || (r.messageHash !== null && r.messageHash !== messageHash)) throw Error('Journal transition rejected');
        return validate({ ...r, state: next, messageHash, updatedAt: now });
      });
      if (!found) throw Error('No pending operation in this account');
      return { records: updated, result: undefined };
    });
  }
  async forgetTerminal(context: Context, id: string): Promise<void> {
    address(context.account); network(context.chain);
    return this.mutate<void>(records => ({ result: undefined, records: records.filter(r =>
      !(r.account === context.account && r.chain === context.chain && r.intentId === id && !isPending(r.state))) }));
  }
}

/** Same-origin IndexedDB transaction serializes reservations across windows. No network or analytics. */
export function indexedDbJournal(factory: IDBFactory, databaseName = 'wallet-gift-pending-v1'): JournalStore {
  if (!/^[a-z0-9-]{1,64}$/.test(databaseName)) throw Error('Invalid journal database');
  function run<T>(mode: 'readonly' | 'readwrite',
    use: (records: readonly PendingTrade[], store: IDBObjectStore) => T): Promise<T> {
    return new Promise<T>((resolve,reject) => {
      let abandoned = false;
      const open = factory.open(databaseName,1);
      open.onupgradeneeded = () => { open.result.createObjectStore('pending'); };
      open.onerror = () => reject(Error('Pending journal unavailable'));
      open.onblocked = () => { abandoned = true; reject(Error('Pending journal upgrade blocked')); };
      open.onsuccess = () => {
        if (abandoned) { open.result.close(); return; }
        const db = open.result;
        db.onversionchange = () => db.close();
        try {
          const tx = mode === 'readwrite'
            ? db.transaction('pending',mode,{ durability: 'strict' })
            : db.transaction('pending',mode);
          if (mode === 'readwrite' && tx.durability !== 'strict') {
            tx.abort();
            throw Error('Strict journal durability unavailable');
          }
          let result: T;
          tx.oncomplete = () => { db.close(); resolve(result); };
          tx.onabort = () => { db.close(); reject(Error('Pending journal transaction failed')); };
          const store = tx.objectStore('pending');
          const read = store.get('records');
          read.onsuccess = () => {
            try {
              const records: unknown = read.result === undefined ? [] : read.result;
              result = use(validateRecords(records),store);
            } catch (error) {
              reject(error);
              tx.abort();
            }
          };
        } catch (error) {
          db.close();
          reject(error);
        }
      };
    });
  }
  return {
    read: () => run('readonly',records => records),
    transact: update => run('readwrite',(records,store) => {
      const change = update(records);
      store.put(validateRecords(change.records),'records');
      return change.result;
    }),
  };
}
