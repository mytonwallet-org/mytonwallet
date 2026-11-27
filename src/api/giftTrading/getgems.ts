import { address, coins, network, timestamp, collectPages } from './protocol.js';
import type { Chain, Offer, Page } from './protocol.js';
import { boundedRead } from './bounded.js';

type JsonObject = Record<string, unknown>;
function object(value:unknown):JsonObject { if(!value || typeof value!=='object' || Array.isArray(value)) throw Error('Invalid object'); return value as JsonObject; }
export type AddressNormalizer = (value: string, chain: Chain) => string;
export type Candidate = Omit<Offer,'gasBudget'> & { gasBudget:null; feeAddress:string; royaltyAddress:string; netBeforeNetworkFee:string };
/** Parse official REST data only. Candidates are neither liquidity proofs nor signing instructions. */
export function parseOffer(value:unknown, chain:Chain, normalize:AddressNormalizer, traits:Readonly<Record<string,string>>):Candidate {
  const raw=object(value); network(chain);
  const addr=(v:unknown)=>{if(typeof v!=='string'||v.length>128)throw Error('Address missing');return address(normalize(v,chain));};
  if(raw.isOffchain!==false || raw.currency!=='TON' || typeof raw.isCollectionOffer!=='boolean') throw Error('Unsupported offer');
  const nft=raw.nftAddress===null?null:addr(raw.nftAddress), collection=addr(raw.collectionAddress);
  if(raw.isCollectionOffer ? nft!==null : nft===null) throw Error('Offer scope mismatch');
  const gross=coins(raw.fullPrice,true), fee=coins(raw.feePrice), royalty=coins(raw.royaltyPrice), profit=coins(raw.profitPrice,true);
  if(gross-fee-royalty!==profit) throw Error('Fee accounting mismatch');
  let remaining=1;
  if(raw.isCollectionOffer) {
    if(!Number.isSafeInteger(raw.maxQuantity) || !Number.isSafeInteger(raw.purchasedQuantity) || Number(raw.purchasedQuantity)<0 || Number(raw.maxQuantity)<0)throw Error('Missing collection offer capacity');
    remaining=Number(raw.maxQuantity)-Number(raw.purchasedQuantity);
    if(remaining<=0)throw Error('Exhausted offer');
  }
  const attrs:Record<string,string>=Object.create(null);
  if(raw.attributes!==undefined) {
    if(!Array.isArray(raw.attributes) || raw.attributes.length>64)throw Error('Invalid attributes');
    for(const entry of raw.attributes) {
      const {trait,values}=object(entry);
      if(typeof trait!=='string' || !trait || trait.length>128 || Object.hasOwn(attrs,trait) || !Array.isArray(values) || values.length<1 || values.length>64 || values.some(v=>typeof v!=='string'||v.length>256))throw Error('Invalid attribute condition');
      const actual=traits[trait];
      if(!Object.hasOwn(traits,trait) || actual===undefined || !values.includes(actual))throw Error('Gift does not match offer');
      attrs[trait]=actual;
    }
  }
  return Object.freeze({id:addr(raw.offerAddress),provider:'getgems',chain,nft,collection,currency:'TON',gross:gross.toString(),fee:fee.toString(),royalty:royalty.toString(),gasBudget:null,expiresAt:timestamp(raw.finishAt),remaining,attributes:Object.freeze(attrs),feeAddress:addr(raw.feeAddress),royaltyAddress:addr(raw.royaltyAddress),netBeforeNetworkFee:profit.toString()});
}
export function parseOfferPage(value:unknown):Page<unknown> {
  const root=object(value);
  if(root.success!==true)throw Error('Provider error');
  const response=object(root.response);
  if(!Array.isArray(response.items) || response.items.length>1000 || (response.cursor!==null && typeof response.cursor!=='string'))throw Error('Invalid offers page');
  return {items:response.items,cursor:response.cursor as string|null};
}
export type ReadTransport = (path:string,signal:AbortSignal)=>Promise<unknown>;
/** Transport is configured by the wallet-operated backend; no shared API secret belongs in a public client. */
export async function readOffers(transport:ReadTransport, kind:'nft'|'collection', target:string, signal:AbortSignal):Promise<unknown[]> {
  address(target);
  if(kind!=='nft' && kind!=='collection')throw Error('Invalid scope');
  return boundedRead(signal, scoped=>collectPages(async(cursor,s)=>parseOfferPage(await transport(`/v1/offers/${kind}/${encodeURIComponent(target)}?limit=100${cursor===null?'':'&after='+encodeURIComponent(cursor)}`,s)),scoped),30000);
}

export type AdvertisedOffer = Readonly<Candidate & {
  scope: 'nft' | 'collection'; executable: false; fundingVerified: false;
}>;

/** The caller supplies a wallet-owned transport and previously identified gift.
 * The two routes must both succeed before any results are returned. */
export async function readAdvertisedOffers(
  transport: ReadTransport, normalize: AddressNormalizer,
  gift: Readonly<{chain:Chain;nft:string;collection:string;traits:Readonly<Record<string,string>>}>,
  signal: AbortSignal, clock: () => number,
): Promise<readonly AdvertisedOffer[]> {
  const chain=network(gift.chain), nft=address(gift.nft), collection=address(gift.collection);
  const traits=Object.freeze({...gift.traits});
  return boundedRead(signal, async scoped=>{
    const unique=new Map<string,{offer:AdvertisedOffer;fingerprint:string}>();
    const conflicts=new Set<string>();
    for(const [scope,target] of [['nft',nft],['collection',collection]] as const){
      const rows=await readOffers(transport,scope,target,scoped);
      for(const raw of rows){
        let candidate:Candidate;
        try { candidate=parseOffer(raw,chain,normalize,traits); }
        catch { continue; }
        if(candidate.collection!==collection||candidate.nft!==(scope==='nft'?nft:null))continue;
        const fingerprint=JSON.stringify({...candidate,attributes:Object.entries(candidate.attributes).sort()});
        const previous=unique.get(candidate.id);
        if(previous&&previous.fingerprint!==fingerprint)conflicts.add(candidate.id);
        else if(!previous)unique.set(candidate.id,{
          offer:Object.freeze({...candidate,scope,executable:false,fundingVerified:false}),fingerprint,
        });
      }
    }
    scoped.throwIfAborted();
    const now=timestamp(clock());
    return Object.freeze([...unique.values()].map(row=>row.offer)
      .filter(offer=>!conflicts.has(offer.id)&&offer.expiresAt>now));
  },30000);
}
export function fixedPriceRequest(nft:string,owner:string,nanoTon:string) {
  return Object.freeze({path:`/v1/nfts/put-on-sale-fix-price/${encodeURIComponent(address(nft))}`,body:Object.freeze({ownerAddress:address(owner),fullPrice:coins(nanoTon,true).toString(),currency:'TON'})});
}
export function cancelSaleRequest(nft:string) { return Object.freeze({path:`/v1/nfts/cancel-fix-price/${encodeURIComponent(address(nft))}`}); }
export function buyRequest(nft:string,version:string) {
  if(typeof version!=='string' || !version || version.length>256 || /[\x00-\x1f]/.test(version))throw Error('Invalid sale version');
  return Object.freeze({path:`/v1/nfts/buy-fix-price/${encodeURIComponent(address(nft))}`,body:Object.freeze({version})});
}
export function acceptOfferRequest(offerCreator:string,nft:string,offer:string) {
  // Follow the published schema literally. Offer creator is the buyer, NOT automatically the signing seller.
  // The transaction response still needs independent decoding, identity checks and emulation.
  return Object.freeze({path:'/v1/offer/accept',body:Object.freeze({userAddress:address(offerCreator),nftAddress:address(nft),offerAddress:address(offer)})});
}
export function createOfferRequest(buyer:string,nft:string,price:string,finishAt:number,now:number) {
  timestamp(finishAt);timestamp(now);
  if(finishAt<=now || finishAt-now>30*86400)throw Error('Invalid offer lifetime');
  return Object.freeze({path:'/v1/offer/nft/create',body:Object.freeze({userAddress:address(buyer),nftAddress:address(nft),price:coins(price,true).toString(),finishAt,forOffchain:false})});
}
export function cancelOfferRequest(offerCreator:string,offer:string,kind:'nft'|'collection') {
  if(kind!=='nft' && kind!=='collection')throw Error('Invalid offer scope');
  return Object.freeze({path:`/v1/offer/${kind}/cancel`,body:Object.freeze({userAddress:address(offerCreator),offerAddress:address(offer)})});
}
