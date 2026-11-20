import {address,coins,decodeReference,network,timestamp} from './protocol.js';
import {resolveSale,validateReview} from './review.js';
import type {Context,ContractPolicy,Review,SaleSnapshot} from './review.js';
import {IntentCoordinator} from './intent.js';
import type {ReviewedIntent,IntentCheck} from './intent.js';
import {freezePlan,validateEmulation} from './transaction.js';
import type {TransactionPlan,EmulationEvidence} from './transaction.js';
import {boundedRead} from './bounded.js';
import {requireProviderExecution} from './execution-capabilities.js';

export type PurchaseProvider = 'wallet-market' | 'getgems';
export type BuyerAccount = Readonly<{context:Context; kind:'software'|'hardware'|'watch-only'|'unsupported'; spendableBalance:string; observedAt:number}>;
export type ListingRead = Readonly<{sale:SaleSnapshot; version:string; blockRootHash:string}>;
export type PurchaseSummary = Readonly<{
  provider:PurchaseProvider; account:string; nft:string; collection:string; seller:string;
  price:string; includedFee:string; includedRoyalty:string; attachedReserve:string;
  walletFeeReserve:string; maximumDebit:string; expiresAt:number;
}>;
export type Purchase = Readonly<{intent:ReviewedIntent; summary:PurchaseSummary; listingVersion:string; accountKind:'software'|'hardware'; code:Readonly<{sale:string;nft:string}>}>;
export interface PurchasePorts {
  /** All chain data/decoders are trusted-wallet boundaries, never marketplace-supplied proof flags. */
  readListing(reference:string,provider:PurchaseProvider,context:Context,signal:AbortSignal):Promise<ListingRead>;
  readAccount(context:Context,signal:AbortSignal):Promise<BuyerAccount>;
  build(quote:Omit<Review,'gasBudget'> & {gasBudget:null},version:string,blockRootHash:string,signal:AbortSignal):Promise<{
    plan:TransactionPlan; gasBudget:string; walletFeeReserve:string; emulation:EmulationEvidence;
  }>;
  recheck(purchase:Purchase,signal:AbortSignal):Promise<{listing:ListingRead; account:BuyerAccount; check:IntentCheck}>;
}
export type PurchasePolicy = Readonly<{
  providers:Readonly<Record<PurchaseProvider,ContractPolicy>>;
  maxGasBudget:string; maxWalletFeeReserve:string;
}>;
function contextCopy(context:Context):Context {return Object.freeze({account:address(context.account),chain:network(context.chain)});}
function policyCopy(p:ContractPolicy):ContractPolicy {
  for(const list of [p.saleCodeHashes,p.nftCodeHashes,p.giftCollections,p.authorities])if(!Array.isArray(list)||list.length>10000)throw Error('Invalid purchase policy');
  return Object.freeze({...p,saleCodeHashes:Object.freeze([...p.saleCodeHashes]),nftCodeHashes:Object.freeze([...p.nftCodeHashes]),giftCollections:Object.freeze([...p.giftCollections]),authorities:Object.freeze([...p.authorities])});
}
function listingCopy(listing:ListingRead):ListingRead {
  if(typeof listing.version!=='string'||listing.version.length<1||listing.version.length>256||/[\x00-\x1f\x7f]/.test(listing.version)
    || !/^[a-f0-9]{64}$/.test(listing.blockRootHash))throw Error('Invalid listing version or snapshot');
  return Object.freeze({sale:Object.freeze({...listing.sale}),version:listing.version,blockRootHash:listing.blockRootHash});
}
function accountCopy(account:BuyerAccount,context:Context,now:number):BuyerAccount {
  if(account.context.account!==context.account||account.context.chain!==context.chain)throw Error('Buyer account changed');
  if(account.kind!=='software'&&account.kind!=='hardware')throw Error('This account cannot purchase');
  if(timestamp(account.observedAt)>timestamp(now)||now-account.observedAt>15)throw Error('Stale buyer balance');
  coins(account.spendableBalance);
  return Object.freeze({...account,context:contextCopy(account.context)});
}

/** Buyer-side foundation. Does not implement a signer, broadcast, marketplace authorization or UI.
 * A configured production reader, verified decoder and actual-app acceptance are still required.
 */
export class PurchaseCoordinator {
  #context:Context;
  #policy:PurchasePolicy;
  #ports:PurchasePorts;
  #intents:IntentCoordinator;
  #current:Purchase|undefined;
  #generation=0;
  constructor(context:Context,policy:PurchasePolicy,ports:PurchasePorts) {
    this.#context=contextCopy(context);this.#intents=new IntentCoordinator(this.#context);
    coins(policy.maxGasBudget);coins(policy.maxWalletFeeReserve);
    this.#policy=Object.freeze({providers:Object.freeze({'wallet-market':policyCopy(policy.providers['wallet-market']),getgems:policyCopy(policy.providers.getgems)}),maxGasBudget:policy.maxGasBudget,maxWalletFeeReserve:policy.maxWalletFeeReserve});
    this.#ports=Object.freeze({readListing:ports.readListing.bind(ports),readAccount:ports.readAccount.bind(ports),build:ports.build.bind(ports),recheck:ports.recheck.bind(ports)});
  }
  cancel():void {++this.#generation;this.#current=undefined;this.#intents.cancel();}
  switchAccount(context:Context):void {this.cancel();this.#context=contextCopy(context);this.#intents.switchAccount(this.#context);}
  async select(reference:string,provider:PurchaseProvider,now:()=>number):Promise<Purchase> {
    this.cancel();
    const generation=this.#generation;
    if(provider!=='wallet-market'&&provider!=='getgems')throw Error('Unsupported purchase provider');
    requireProviderExecution(provider,'buy');
    if(decodeReference(reference,this.#context.chain).kind!=='sale')throw Error('Expected fixed-price listing');
    let summary!:PurchaseSummary,listingVersion!:string,accountKind!:'software'|'hardware',code!:Readonly<{sale:string;nft:string}>;
    const intent=await this.#intents.prepare(async(context,signal)=>{
      const [read,accountRead]=await Promise.all([
        boundedRead(signal,s=>this.#ports.readListing(reference,provider,context,s)),
        boundedRead(signal,s=>this.#ports.readAccount(context,s)),
      ]);
      signal.throwIfAborted();
      const listing=listingCopy(read),account=accountCopy(accountRead,context,now());
      const resolved=resolveSale(reference,context,listing.sale,this.#policy.providers[provider],now());
      const quote=Object.freeze({...resolved,provider,context:contextCopy(context),reference:Object.freeze({...resolved.reference})});
      const built=await boundedRead(signal,s=>this.#ports.build(quote,listing.version,listing.blockRootHash,s));
      signal.throwIfAborted();
      const plan=freezePlan(built.plan,now()),price=coins(quote.amount,true),walletFee=coins(built.walletFeeReserve),gas=coins(built.gasBudget);
      const sent=plan.messages.reduce((total,m)=>total+coins(m.amount,true),0n);
      // Marketplace fee and royalty are INCLUDED in the listing price, never added twice.
      if(sent<price||sent-price+walletFee!==gas||gas>coins(this.#policy.maxGasBudget)||walletFee>coins(this.#policy.maxWalletFeeReserve))throw Error('Unexpected purchase cost or fee budget');
      const total=coins((sent+walletFee).toString(),true);
      if(total>coins(account.spendableBalance))throw Error('Insufficient spendable balance');
      accountCopy(account,context,now());
      const review=Object.freeze({...quote,gasBudget:gas.toString()});validateReview(review,context,now());
      validateEmulation(plan,built.emulation,review.chainStateHash,now());
      summary=Object.freeze({provider,account:context.account,nft:review.reference.nft,collection:listing.sale.collection,seller:review.counterparty,
        price:price.toString(),includedFee:review.fee,includedRoyalty:review.royalty,attachedReserve:(sent-price).toString(),walletFeeReserve:walletFee.toString(),maximumDebit:total.toString(),expiresAt:review.expiresAt});
      listingVersion=listing.version;accountKind=account.kind as 'software'|'hardware';
      code=Object.freeze({sale:listing.sale.codeHash,nft:listing.sale.nftCodeHash});
      return {review,plan};
    },now);
    if(generation!==this.#generation)throw Error('Superseded purchase');
    const result=Object.freeze({intent,summary,listingVersion,accountKind,code});this.#current=result;return result;
  }
  async confirm(purchase:Purchase,handoff:(intent:ReviewedIntent)=>undefined,now:()=>number):Promise<void> {
    if(purchase!==this.#current)throw Error('Purchase is not current');
    this.#current=undefined;
    await this.#intents.confirm(purchase.intent,async(intent,signal)=>{
      const checked=await this.#ports.recheck(purchase,signal);
      signal.throwIfAborted();
      const account=accountCopy(checked.account,intent.review.context,now()),listing=listingCopy(checked.listing);
      const r=intent.review;
      const reference=`ton-gift-trade://v1/sale?network=${r.reference.chain}&nft=${r.reference.nft}&contract=${r.reference.contract}`;
      const latest=resolveSale(reference,r.context,listing.sale,this.#policy.providers[purchase.summary.provider],now());
      if(account.kind!==purchase.accountKind||coins(account.spendableBalance)<coins(purchase.summary.maximumDebit))throw Error('Buyer account or available funds changed');
      if(listing.version!==purchase.listingVersion||listing.blockRootHash!==checked.check.canonicalBlockRoot)throw Error('Listing version or verified block changed');
      if(listing.sale.collection!==purchase.summary.collection||listing.sale.codeHash!==purchase.code.sale||listing.sale.nftCodeHash!==purchase.code.nft)throw Error('Gift collection or contract implementation changed');
      for(const key of ['counterparty','amount','fee','royalty','feeRecipient','royaltyRecipient','authority','chainStateHash'] as const)if(latest[key]!==r[key])throw Error('Listing changed; a new review is required');
      return checked.check;
    },handoff,now);
  }
}
