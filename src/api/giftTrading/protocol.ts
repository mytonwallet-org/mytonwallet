import { boundedRead } from './bounded.js';
/** Experimental reference format, not a registered wallet deep link or an authorization to transact. */
export type Chain = '-239' | '-3';
export type MarketKind = 'sale' | 'offer';
export type MarketReference = Readonly<{ version: 1; chain: Chain; kind: MarketKind; nft: string; contract: string }>;
export const MAX_COINS = (1n << 120n) - 1n; // TON VarUInteger 16

export function address(value: unknown): string {
  // Wire format is deliberately canonical. Wallets normalize friendly addresses before encoding.
  if (typeof value !== 'string' || !/^0:[0-9a-f]{64}$/.test(value)) throw new Error('Invalid canonical workchain-0 address');
  return value;
}
export function coins(value: unknown, positive = false): bigint {
  if (typeof value !== 'string' || !/^(0|[1-9][0-9]{0,36})$/.test(value)) throw new Error('Invalid nanoTON amount');
  const result = BigInt(value);
  if (result > MAX_COINS || (positive && result === 0n)) throw new Error('Amount out of range');
  return result;
}
export function timestamp(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > 0xffffffff) throw new Error('Invalid timestamp');
  return value;
}
export function network(value: unknown): Chain {
  if (value !== '-239' && value !== '-3') throw new Error('Unsupported network');
  return value;
}
export function parseTonInput(text: string): string {
  if (!/^(0|[1-9][0-9]{0,27})(\.[0-9]{1,9})?$/.test(text)) throw new Error('Enter a positive TON amount with up to 9 decimals');
  const [whole, fraction = ''] = text.split('.');
  const value = (BigInt(whole!) * 1000000000n + BigInt(fraction.padEnd(9, '0'))).toString();
  coins(value, true);
  return value;
}
export function formatTon(value: string): string {
  const amount = coins(value);
  const fraction = (amount % 1000000000n).toString().padStart(9, '0').replace(/0+$/, '');
  return `${amount / 1000000000n}${fraction ? '.' + fraction : ''}`;
}
export function encodeReference(ref: MarketReference): string {
  if (ref.version !== 1 || (ref.kind !== 'sale' && ref.kind !== 'offer')) throw new Error('Unsupported reference');
  return `ton-gift-trade://v1/${ref.kind}?network=${network(ref.chain)}&nft=${address(ref.nft)}&contract=${address(ref.contract)}`;
}
export function decodeReference(text: string, expectedChain: Chain): MarketReference {
  if (typeof text !== 'string' || text.length > 256) throw new Error('Invalid reference');
  const m = /^ton-gift-trade:\/\/v1\/(sale|offer)\?network=(-239|-3)&nft=(0:[0-9a-f]{64})&contract=(0:[0-9a-f]{64})$/.exec(text);
  if (!m || m[2] !== network(expectedChain)) throw new Error('Invalid reference or wrong network');
  // The reference never includes price, beneficiary, code, StateInit, payload, or provider URL.
  return Object.freeze({ version: 1, kind: m[1] as MarketKind, chain: network(m[2]), nft: address(m[3]), contract: address(m[4]) });
}

export type Asset = Readonly<{ chain: Chain; address: string; collection: string; owner: string }>;
export type Offer = Readonly<{
  id: string; provider: string; chain: Chain; nft: string | null; collection: string;
  currency: 'TON'; gross: string; fee: string; royalty: string; gasBudget: string;
  expiresAt: number; remaining: number; attributes: Readonly<Record<string, string>>;
}>;
export type QuoteResult = Readonly<{ offer: Offer; netBeforeNetworkFee: string; netAfterGasBudget: string }>;
/** Ranking is for displayed quotes only. No quote is executable until chain/contract verification and emulation. */
export function rankOffers(offers: readonly Offer[], asset: Asset, traits: Readonly<Record<string, string>>, now: number): QuoteResult[] {
  timestamp(now); network(asset.chain); address(asset.address); address(asset.collection); address(asset.owner);
  if (!Array.isArray(offers) || offers.length > 10000 || !traits || Object.keys(traits).length > 64) throw Error('Offer budget exceeded');
  const result: QuoteResult[] = [];
  // A provider must not be able to make a conflicting duplicate win by ordering it first.
  const counts = new Map<string, number>();
  for (const offer of offers) {
    if (!offer || typeof offer.provider !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(offer.provider)
      || typeof offer.id !== 'string' || !/^0:[0-9a-f]{64}$/.test(offer.id)) continue;
    const id = `${offer.provider}:${offer.id}`;
    counts.set(id, (counts.get(id) ?? 0) + 1);
  }
  for (const offer of offers) {
    try {
      const id = `${offer.provider}:${address(offer.id)}`;
      if (counts.get(id) !== 1) throw new Error('Duplicate quote');
      if (!/^[a-z][a-z0-9-]{0,31}$/.test(offer.provider) || network(offer.chain) !== asset.chain || offer.currency !== 'TON') continue;
      if (address(offer.collection) !== asset.collection || (offer.nft !== null && address(offer.nft) !== asset.address)) continue;
      if (timestamp(offer.expiresAt) <= now || !Number.isSafeInteger(offer.remaining) || offer.remaining <= 0) continue;
      if (!offer.attributes || Array.isArray(offer.attributes) || Object.keys(offer.attributes).length > 64
        || Object.entries(offer.attributes).some(([k,v]) => k.length > 128 || typeof v !== 'string' || v.length > 256 || !Object.hasOwn(traits,k) || traits[k] !== v)) continue;
      const gross = coins(offer.gross, true), fee = coins(offer.fee), royalty = coins(offer.royalty), gas = coins(offer.gasBudget);
      const net = gross - fee - royalty;
      if (net <= gas) continue;
      result.push({ offer: Object.freeze({ ...offer, attributes: Object.freeze({ ...offer.attributes }) }), netBeforeNetworkFee: net.toString(), netAfterGasBudget: (net-gas).toString() });
    } catch { /* Malformed third-party offer cannot become a selectable quote. */ }
  }
  return result.sort((a,b) => {
    const diff = BigInt(b.netAfterGasBudget) - BigInt(a.netAfterGasBudget);
    return diff === 0n ? `${a.offer.provider}:${a.offer.id}`.localeCompare(`${b.offer.provider}:${b.offer.id}`) : diff > 0n ? 1 : -1;
  });
}

export type Page<T> = { items: T[]; cursor: string | null };
export async function collectPages<T>(read: (cursor: string | null, signal: AbortSignal) => Promise<Page<T>>, signal: AbortSignal, maxPages = 100, maxItems = 10000): Promise<T[]> {
  if (!Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > 10000) throw new Error('Invalid page budget');
  if (!Number.isSafeInteger(maxItems) || maxItems < 1 || maxItems > 10000) throw Error('Invalid item budget');
  const items: T[] = [], seen = new Set<string>();
  let cursor: string | null = null;
  for (let page = 0; page < maxPages; page++) {
    signal.throwIfAborted();
    const response = await boundedRead(signal, s => read(cursor,s));
    signal.throwIfAborted();
    if (!response || !Array.isArray(response.items) || response.items.length > 1000) throw new Error('Invalid page');
    if (items.length + response.items.length > maxItems) throw Error('Total item budget exceeded');
    items.push(...response.items);
    if (response.cursor === null) return items;
    if (typeof response.cursor !== 'string' || !response.cursor || response.cursor.length > 2048 || seen.has(response.cursor)) throw new Error('Non-progressing page');
    seen.add(response.cursor); cursor = response.cursor;
  }
  // Never advertise the best market-wide price from a silently truncated result.
  throw new Error('Incomplete inventory of offers');
}
