import { address, coins, decodeReference, encodeReference, network, timestamp } from './protocol.js';
import type { Chain } from './protocol.js';
import { giftLabel } from './privacy.js';
export type MarketRecord = Readonly<{ reference: string; collection: string; seller: string; price: string;
  title: string; status: 'active' | 'sold' | 'cancelled'; revision: number }>;
export type MarketSnapshot = Readonly<{ version: 1; chain: Chain; blockHash: string; sequence: number;
  observedAt: number; complete: boolean; records: readonly MarketRecord[] }>;
/** Discovery is untrusted advertising. It never chooses transaction messages or recipients. */
export class LocalMarketIndex {
  #snapshot: MarketSnapshot | undefined;
  #generation = 0;
  replace(input: MarketSnapshot): void {
    if (input.version !== 1 || !/^[a-f0-9]{64}$/.test(input.blockHash) || !Number.isSafeInteger(input.sequence)
      || input.sequence < 0 || typeof input.complete !== 'boolean' || !Array.isArray(input.records) || input.records.length > 10000) throw Error('Invalid market snapshot');
    network(input.chain); timestamp(input.observedAt);
    if (this.#snapshot && (input.chain !== this.#snapshot.chain || input.sequence < this.#snapshot.sequence
      || (input.sequence === this.#snapshot.sequence && input.blockHash !== this.#snapshot.blockHash))) throw Error('Network or snapshot regression');
    const byId = new Map<string,MarketRecord>();
    for (const row of input.records) {
      const reference = encodeReference(decodeReference(row.reference,input.chain)); address(row.collection); address(row.seller); coins(row.price,true);
      if (!['active','sold','cancelled'].includes(row.status) || !Number.isSafeInteger(row.revision) || row.revision < 0) throw Error('Invalid market record');
      const value = Object.freeze({ reference, collection: row.collection, seller: row.seller, price: row.price,
        title: giftLabel(row.title), status: row.status, revision: row.revision });
      const previous = byId.get(reference);
      if (previous && JSON.stringify(previous) !== JSON.stringify(value)) throw Error('Contradictory duplicate listing');
      byId.set(reference,value);
    }
    this.#snapshot = Object.freeze({ version: 1, chain: input.chain, blockHash: input.blockHash, sequence: input.sequence,
      observedAt: input.observedAt, complete: input.complete, records: Object.freeze([...byId.values()]) });
    ++this.#generation;
  }
  page(query: Readonly<{ search?: string; collection?: string; kind?: 'sale' | 'offer'; limit: number; cursor?: string }>) {
    const snapshot = this.#snapshot;
    if (!snapshot || !Number.isInteger(query.limit) || query.limit < 1 || query.limit > 100) throw Error('Market is unavailable or page is invalid');
    const search = giftLabel(query.search ?? '',120).toLowerCase();
    const term = query.search ? search : '';
    if (query.collection) address(query.collection);
    if (query.kind && !['sale','offer'].includes(query.kind)) throw Error('Invalid listing kind');
    // Cursor is bound to snapshot AND query. Editing it can only affect discovery, never execution.
    const binding = JSON.stringify([snapshot.blockHash,this.#generation,term,query.collection ?? '',query.kind ?? '',query.limit]);
    let offset = 0;
    if (query.cursor) {
      if (query.cursor.length > 1500) throw Error('Invalid cursor');
      const cursor = JSON.parse(query.cursor) as unknown;
      if (!Array.isArray(cursor) || cursor.length !== 2 || cursor[0] !== binding || !Number.isSafeInteger(cursor[1]) || cursor[1] < 0) throw Error('Snapshot or query changed');
      offset = cursor[1] as number;
    }
    const rows = snapshot.records.filter(r => r.status === 'active' && (!term || r.title.toLowerCase().includes(term))
      && (!query.collection || r.collection === query.collection) && (!query.kind || decodeReference(r.reference,snapshot.chain).kind === query.kind))
      .sort((a,b) => coins(a.price) < coins(b.price) ? -1 : coins(a.price) > coins(b.price) ? 1 : a.reference.localeCompare(b.reference));
    if (offset > rows.length) throw Error('Cursor exceeds snapshot');
    const items = Object.freeze(rows.slice(offset,offset+query.limit));
    return Object.freeze({ items, knownCount: rows.length, complete: snapshot.complete, blockHash: snapshot.blockHash,
      observedAt: snapshot.observedAt, next: offset+items.length < rows.length ? JSON.stringify([binding,offset+items.length]) : null });
  }
}
