import { jsonResponseSizeAllowed, readBoundedUtf8 } from './bounded.js';
import { address, coins, decodeReference, timestamp } from './protocol.js';
import { boundedJson } from './privacy.js';
import type { IntentCheck, ReviewedIntent } from './intent.js';
import type { Review, TradeAction } from './review.js';
import { freezePlan } from './transaction.js';
import type { TransactionPlan } from './transaction.js';

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Expected laboratory object');
  return value as Record<string,unknown>;
}
function matching<T extends string>(value: unknown, pattern: RegExp): T {
  if (typeof value !== 'string' || !pattern.test(value)) throw Error('Invalid laboratory field');
  return value as T;
}
function count(value: unknown, maximum = Number.MAX_SAFE_INTEGER): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > maximum) throw Error('Invalid laboratory count');
  return value;
}
function array(value: unknown, max: number): unknown[] {
  if (!Array.isArray(value) || value.length > max) throw Error('Invalid laboratory list');
  return value;
}
function envelope(value: unknown) {
  const payload=object(value);
  if(payload.labOnly!==true)throw Error('Expected laboratory response');
  return payload;
}
const hex=/^[a-f0-9]{64}$/;
const brandPattern=/^(mytonwallet|tonkeeper)$/;
type Brand = 'mytonwallet'|'tonkeeper';
const chain=(value: unknown)=>matching<'-239'>(value,/^-239$/);
export function decodeLabState(value: unknown) {
  const v=envelope(value), p=object(v.giftProfile);
  return {
    account:address(v.account),brand:matching<Brand>(v.brand,brandPattern),chain:chain(v.chain),revision:count(v.revision),
    balance:coins(v.balance).toString(),
    giftProfile:{id:matching(p.id,/^[a-z0-9-]{1,64}$/),codeHash:matching(p.codeHash,hex),collection:address(p.collection)},
    gifts:array(v.gifts,1024).map(item=>{
      const gift=object(item);
      if(typeof gift.title!=='string'||gift.title.length>2048)throw Error('Invalid gift title');
      return {address:address(gift.address),owner:address(gift.owner),title:gift.title};
    }),
    listings:array(v.listings,1024).map(item=>{
      const listing=object(item);
      const reference=matching(listing.reference,/^.{1,256}$/), ref=decodeReference(reference,'-239');
      if(ref.nft!==listing.nft||ref.contract!==listing.contract||ref.kind!==listing.kind)throw Error('Inconsistent listing');
      const phase=count(listing.phase,11);
      if((listing.expired!==undefined&&typeof listing.expired!=='boolean')
        ||(listing.available!==undefined&&typeof listing.available!=='boolean'))throw Error('Invalid listing availability');
      const expired=listing.expired!==false;
      const available=listing.available===true;
      if(available&&(phase!==2||expired))throw Error('Inconsistent listing availability');
      const seller=listing.seller==null?null:address(listing.seller);
      const buyer=listing.buyer==null?null:address(listing.buyer);
      return {...ref,reference,price:coins(listing.price,true).toString(),phase,expired,available,seller,buyer};
    }),
  };
}
export function decodeLabReceipt(value: unknown) {
  const v=envelope(value);
  if(v.found===false)return undefined;
  if(v.found!==undefined&&v.found!==true)throw Error('Invalid receipt availability');
  const outcome=matching<'confirmed'|'pending'>(v.outcome,/^(confirmed|pending)$/);
  const stage=matching<'deploy'|'deposit'|'offer-funding'|'operation'>(v.stage,/^(deploy|deposit|offer-funding|operation)$/);
  const status=matching(v.status,/^(awaiting-deposit|emulator-complete|awaiting-proof|awaiting-continuation|pending|awaiting-credit|partial-credit)$/);
  if ((stage==='deploy' && status!=='awaiting-deposit')
      || (stage!=='deploy' && status==='awaiting-deposit')
      || (outcome==='confirmed')!==(status==='awaiting-deposit'||status==='emulator-complete')
      || (stage!=='operation'&&outcome==='pending')) throw Error('Inconsistent laboratory receipt');
  return {
    found:v.found===true, intentId:matching(v.intentId,hex), account:address(v.account),chain:chain(v.chain),
    messageHash:matching(v.messageHash,hex), outcome,status,stage,
    observedOwner:v.observedOwner===undefined?undefined:address(v.observedOwner),
  };
}
export type LabReceipt = ReturnType<typeof decodeLabReceipt>;

export function matchesLabReceipt(receipt: LabReceipt, expected: {
  id: string; account: string; chain: string; action: TradeAction;
}, stage?: NonNullable<LabReceipt>['stage']): receipt is NonNullable<LabReceipt> {
  if (!receipt || receipt.intentId!==expected.id || receipt.account!==expected.account
      || receipt.chain!==expected.chain || (stage && receipt.stage!==stage)) return false;
  if (expected.action==='list') return receipt.stage==='deploy'||receipt.stage==='deposit';
  if (expected.action==='make-offer') return receipt.stage==='offer-funding';
  return receipt.stage==='operation';
}

type SelectedListing = Pick<ReturnType<typeof decodeLabState>['listings'][number],
  'contract' | 'kind' | 'nft' | 'price' | 'seller' | 'buyer'>;

export function decodeLabPreparation(value: unknown, selection: {
  action: TradeAction; nft: string; price: string; listing: SelectedListing | undefined;
}): { review: Review; plan: TransactionPlan } {
  const reply = envelope(value);
  const review = object(reply.review);
  const reference = object(review.reference);
  const {action, listing} = selection;
  const kind = action === 'list' || action === 'buy' || action === 'cancel-sale' ? 'sale' : 'offer';
  const amount = action === 'cancel-sale' || action === 'cancel-offer' ? '0' : listing?.price ?? selection.price;
  const counterparty = action === 'buy' ? listing?.seller : action === 'accept-offer' ? listing?.buyer : undefined;
  if (review.action !== action || reference.nft !== address(selection.nft) || reference.kind !== kind
      || review.amount !== amount || (!listing && action !== 'list' && action !== 'make-offer')
      || (listing && (reference.contract !== listing.contract || listing.nft !== selection.nft || listing.kind !== kind))
      || ((action === 'buy' || action === 'accept-offer') && review.counterparty !== address(counterparty))) {
    throw Error('Preparation does not match the selected gift and terms');
  }
  // The session checks and freezes the full review and plan before either reaches the display.
  return { review: review as unknown as Review, plan: object(reply.plan) as unknown as TransactionPlan };
}

export function decodeLabVerification(value: unknown, intent: ReviewedIntent, now: number): IntentCheck {
  const reply = envelope(value);
  const emulation = object(reply.emulation);
  const snapshot = intent.review.chainStateHash;
  const at = timestamp(reply.observedAt);
  if (reply.intentId !== intent.id || reply.canonicalBlockRoot !== snapshot || emulation.stateHash !== snapshot
      || timestamp(emulation.observedAt) !== at || at > timestamp(now) || now - at > 15
      || emulation.allActionsSucceeded !== true || emulation.verifiedRecipients !== true
      || emulation.verifiedOwnership !== true || emulation.feesWithinBudget !== true) {
    throw Error('Unverified laboratory snapshot');
  }
  const plan = freezePlan(object(emulation.plan) as unknown as TransactionPlan, now);
  return { intentId: intent.id, canonicalBlockRoot: snapshot, observedAt: at, emulation: {
    plan, stateHash: snapshot, observedAt: at, allActionsSucceeded: true,
    verifiedRecipients: true, verifiedOwnership: true, feesWithinBudget: true,
  } };
}

export type LabContinuation = ReturnType<typeof continuationTerms> & {reviewHash:string};
function continuationTerms(value: unknown) {
  const v=object(value);
  const phase=count(v.phase,8);
  const step=matching<'delivery-proof'|'payout'|'refund'>(v.step,/^(delivery-proof|payout|refund)$/);
  if(((phase===4||phase===8) && step==='delivery-proof')||(phase===5 && step==='payout')||(phase===6 && step==='refund')){
    const query=matching(v.query,/^(0|[1-9][0-9]{0,19})$/);
    if(BigInt(query)>0xffffffffffffffffn)throw Error('Invalid continuation query');
    const payouts=array(v.payouts,2);
    if ((phase===8&&payouts.length!==0)||(phase===6&&payouts.length!==1)
        ||((phase===4||phase===5)&&payouts.length===0)) throw Error('Inconsistent continuation payouts');
    return {
      id:matching(v.id,hex),account:address(v.account),chain:chain(v.chain),nft:address(v.nft),market:address(v.market),
      revision:count(v.revision),phase,query,expectedOwner:address(v.expectedOwner),
      payouts:payouts.map(item=>{
        const payout=object(item);
        return {recipient:address(payout.recipient),amount:coins(payout.amount,true).toString()};
      }),
      contribution:coins(v.contribution,true).toString(),expiresAt:timestamp(v.expiresAt),step,
    };
  }
  throw Error('Inconsistent continuation phase');
}
async function digestTerms(terms: ReturnType<typeof continuationTerms>) {
  const bytes=new TextEncoder().encode('gift-lab-continuation-v1\n'+JSON.stringify(terms));
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  return Array.from(new Uint8Array(digest), byte=>byte.toString(16).padStart(2,'0')).join('');
}
export async function labContinuationDigest(value: unknown) {
  return digestTerms(continuationTerms(value));
}
export async function decodeLabContinuation(value: unknown, scope: {id:string;account:string;chain:string;nft:string;market:string}, now: number): Promise<LabContinuation|undefined> {
  const v=envelope(value);
  if(v.found===false)return undefined;
  if(v.found!==true)throw Error('Invalid continuation availability');
  const terms=continuationTerms(v), reviewHash=matching(v.reviewHash,hex);
  if(terms.id!==scope.id||terms.account!==scope.account||terms.chain!==scope.chain||terms.nft!==scope.nft||terms.market!==scope.market
    ||terms.expiresAt<=timestamp(now)||terms.expiresAt>now+60||await digestTerms(terms)!==reviewHash)throw Error('Unverified continuation terms');
  return {...terms,reviewHash};
}
export async function readLabJson(response: Response, signal: AbortSignal) {
  if(!response.ok||!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type')??'')
    ||!jsonResponseSizeAllowed(response.headers.get('content-length'))||!response.body||signal.aborted){
    void response.body?.cancel().catch(()=>{});
    signal.throwIfAborted();
    throw Error('Invalid laboratory response');
  }
  const reader=response.body.getReader();
  try{
    const text=await readBoundedUtf8(reader,signal,'Laboratory');
    signal.throwIfAborted();
    return envelope(boundedJson(text));
  }finally{
    void reader.cancel().catch(()=>{});
    reader.releaseLock();
  }
}
