import { address, collectPages, decodeReference, encodeReference, network, timestamp } from './protocol.js';
import type { Chain, MarketReference, Page } from './protocol.js';
import { assertSaleFreshness, resolveSale } from './review.js';
import type { Context, ContractPolicy, SaleSnapshot } from './review.js';
import { boundedRead } from './bounded.js';

export type Block = Readonly<{ chain: Chain; seqno: number; rootHash: string; observedAt: number }>;
export type DirectoryPage = Page<string> & { block: Block };
export type VerifiedSale = Readonly<{ reference: string; sale: SaleSnapshot; block: Block }>;
export interface DirectoryPorts {
  // These endpoints provide hints only; they cannot supply authoritative prices or recipients.
  page(cursor: string | null, signal: AbortSignal): Promise<DirectoryPage>;
  // The independent chain reader must resolve NFT ownership and sale data at the SAME block.
  read(reference: MarketReference, block: Block, signal: AbortSignal): Promise<Readonly<{ sale: SaleSnapshot; block: Block }>>;
  canonical(block: Block, signal: AbortSignal): Promise<boolean>;
}
function validateBlock(block: Block, chain: Chain, now: number): void {
  if (block.chain !== chain || !Number.isSafeInteger(block.seqno) || block.seqno < 0
    || !/^[a-f0-9]{64}$/.test(block.rootHash) || timestamp(block.observedAt) > timestamp(now)
    || now - block.observedAt > 30) throw Error('Stale or invalid directory block');
}
function sameBlock(a: Block, b: Block): boolean {
  return a.chain === b.chain && a.seqno === b.seqno && a.rootHash === b.rootHash && a.observedAt === b.observedAt;
}
export async function loadDirectory(ports: DirectoryPorts, context: Context, policy: ContractPolicy,
  signal: AbortSignal, now: () => number): Promise<readonly VerifiedSale[]> {
  // Snapshot caller-owned configuration before the first await.
  const frozenContext = Object.freeze({ account: address(context.account), chain: network(context.chain) });
  for (const list of [policy.saleCodeHashes, policy.nftCodeHashes, policy.giftCollections, policy.authorities]) {
    if (!Array.isArray(list) || list.length > 10000) throw Error('Invalid policy budget');
  }
  const frozenPolicy = Object.freeze({ ...policy, saleCodeHashes: Object.freeze([...policy.saleCodeHashes]),
    nftCodeHashes: Object.freeze([...policy.nftCodeHashes]), giftCollections: Object.freeze([...policy.giftCollections]),
    authorities: Object.freeze([...policy.authorities]) });
  const frozenPorts = Object.freeze({ page: ports.page.bind(ports), read: ports.read.bind(ports), canonical: ports.canonical.bind(ports) });
  return boundedRead(signal, scoped => loadPinnedDirectory(frozenPorts, frozenContext, frozenPolicy, scoped, now), 30000);
}
async function loadPinnedDirectory(ports: DirectoryPorts, context: Context, policy: ContractPolicy,
  signal: AbortSignal, now: () => number): Promise<readonly VerifiedSale[]> {
  let block: Block | undefined;
  const refs = await collectPages(async (cursor, s) => {
    const page = await ports.page(cursor, s);
    validateBlock(page.block, context.chain, now());
    if (block && !sameBlock(page.block, block)) throw Error('Directory changed while paging');
    block = Object.freeze({ ...page.block });
    return page;
  }, signal, 100, 5000);
  if (!block) throw Error('Missing directory block');
  const pinned = block;
  if (refs.length > 5000) throw Error('Directory requires narrower filter');
  const unique = new Set<string>();
  const listings: VerifiedSale[] = [];
  for (const text of refs) {
    signal.throwIfAborted();
    const ref = decodeReference(text, context.chain);
    if (ref.kind !== 'sale') throw Error('Unexpected directory entry');
    const id = encodeReference(ref);
    if (unique.has(id)) continue;
    unique.add(id);
    const read = await boundedRead(signal, s => ports.read(ref, pinned, s));
    signal.throwIfAborted();
    validateBlock(read.block, context.chain, now());
    if (!sameBlock(read.block, pinned)) throw Error('Sale and NFT state are from another block');
    const sale = Object.freeze({ ...read.sale });
    resolveSale(id, context, sale, policy, now(), 'browse');
    listings.push(Object.freeze({ reference: id, sale: Object.freeze({ ...sale }), block: pinned }));
  }
  validateBlock(pinned, context.chain, now());
  if (await boundedRead(signal, s => ports.canonical(pinned, s)) !== true) throw Error('Directory block is no longer canonical');
  signal.throwIfAborted();
  // Exact integer price order; neither wallet brand nor indexer ranking affects it.
  listings.sort((a, b) => {
    const delta = BigInt(a.sale.fullPrice) - BigInt(b.sale.fullPrice);
    return delta === 0n ? a.reference.localeCompare(b.reference) : delta > 0n ? 1 : -1;
  });
  // A canonical block can outlive the shorter per-sale freshness policy.
  const checkedAt = now();
  validateBlock(pinned, context.chain, checkedAt);
  for (const { sale } of listings) assertSaleFreshness(sale.observedAt, checkedAt, policy.maxAgeSeconds);
  return Object.freeze(listings);
}

// Settlement validation lives separately from discovery; an indexer listing is not a receipt.
export { settlementStatus } from './settlement.js';
export type { TradeExpectation, Settlement } from './settlement.js';
