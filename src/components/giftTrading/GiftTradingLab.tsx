import React, { useEffect, useRef, useState } from '../../lib/teact/teact';
import { TradingSession } from '../../api/giftTrading/trading-session';
import { PendingJournal, indexedDbJournal } from '../../api/giftTrading/journal';
import { parseTonInput, formatTon, decodeReference } from '../../api/giftTrading/protocol';
import { boundedRead } from '../../api/giftTrading/bounded';
import { readAdvertisedOffers } from '../../api/giftTrading/getgems';
import type { AdvertisedOffer } from '../../api/giftTrading/getgems';
import { decodeLabState, decodeLabReceipt, decodeLabContinuation, decodeLabPreparation, decodeLabVerification, matchesLabReceipt, readLabJson } from '../../api/giftTrading/lab-response';
import type { LabReceipt, LabContinuation } from '../../api/giftTrading/lab-response';
import { giftLabel } from '../../api/giftTrading/privacy';
import type { ReviewedIntent } from '../../api/giftTrading/intent';
import type { TradeAction } from '../../api/giftTrading/review';
import { createLabPolicy } from './GiftTradingLabPolicy';
import './GiftTradingLab.css';
import MyTonWalletStandardConfirmation, { type StandardLabRequest } from './MyTonWalletStandardConfirmation';

type LabState = ReturnType<typeof decodeLabState>;
type Listing = LabState['listings'][number];
type Continuation = LabContinuation & {policyRevision:string;action:TradeAction};
const actions: [TradeAction,string][] = [['list','List gift'],['buy','Buy'],['cancel-sale','Cancel sale'],['make-offer','Make offer'],['accept-offer','Accept offer'],['cancel-offer','Cancel offer']];
const syntheticAccounts = {
  mytonwallet:'0:db9bf0f27572f887e9c911d994aa4ee50d91cf44a5f45cf14ad1a6b1765f41c9',
  tonkeeper:'0:c8d79aa4cb55b2ff9766415a2ece52ba670bfe2d330a1e9a41e212ed19e874f7',
} as const;
type SyntheticBrand = keyof typeof syntheticAccounts;
function marketAction(listing: Listing, gift: LabState['gifts'][number] | undefined, account: string) {
  if (!listing.available || !gift) return undefined;
  if (listing.kind === 'sale') return gift.owner === listing.contract && listing.seller && listing.seller !== account
    ? 'buy' : undefined;
  return gift.owner === account && listing.buyer && listing.buyer !== account ? 'accept-offer' : undefined;
}
function listingMatchesAction(listing: Listing, gift: LabState['gifts'][number] | undefined, account: string, action: TradeAction) {
  if (action === 'list') return listing.kind === 'sale' && listing.phase === 1 && !listing.expired
    && listing.seller === account && gift?.owner === account;
  if (action === 'cancel-sale') return listing.kind === 'sale' && listing.phase === 2 && listing.seller === account;
  if (action === 'cancel-offer') return listing.kind === 'offer' && listing.phase === 2 && listing.buyer === account;
  return marketAction(listing,gift,account) === action;
}
function listingStatus(listing: Listing) {
  if (listing.phase === 9) return 'Sold';
  if (listing.phase === 10) return 'Cancelled';
  if (listing.expired) return 'Expired';
  if (listing.phase === 1) return 'Awaiting gift deposit';
  if (listing.available) return 'Available';
  if (listing.phase === 2) return 'Unavailable';
  return 'Settlement pending';
}
function payoutRole(step: LabContinuation['step'], index: number) {
  if (step === 'refund') return 'Offer refund';
  return index === 0 ? 'Seller payout' : 'Royalty payout';
}
async function request(method: 'state'|'prepare'|'verify'|'execute'|'reconcile'|'review-continuation'|'resume'|'advertised-offers',
  input: object, signal = new AbortController().signal) {
  if (!['127.0.0.1','localhost'].includes(location.hostname)) throw Error('Local test build only');
  // A deadline stops waiting only. A dispatched mutation may still complete.
  return boundedRead(signal,async scoped=>{
    const response = await fetch('/__gift_lab/'+method,{method:'POST',credentials:'omit',redirect:'error',
      referrerPolicy:'no-referrer',cache:'no-store',headers:{'Content-Type':'application/json'},
      body:JSON.stringify(input),signal:scoped});
    return readLabJson(response,scoped);
  });
}
/** Actual app component, compiled out by default. Synthetic data and an emulator interceptor only. */
export default function GiftTradingLab({ onClose }: { onClose?: () => void }) {
  const [standardRequest,setStandardRequest]=useState<StandardLabRequest | undefined>();
  const standardPending=useRef<StandardLabRequest | undefined>();
  const standardMounted=useRef(true);
  useEffect(()=>{standardMounted.current=true;return()=>{standardMounted.current=false;standardPending.current?.cancel();};},[]);
  function requestStandardConfirmation(intent:ReviewedIntent,signal:AbortSignal):Promise<undefined> {
    signal.throwIfAborted();standardPending.current?.cancel();
    return new Promise((resolve,reject)=>{
      let finished=false;
      const finish=(accepted:boolean)=>{
        if(finished)return;finished=true;signal.removeEventListener('abort',abort);
        const current=standardPending.current===entry;
        if(current){standardPending.current=undefined;if(standardMounted.current)setStandardRequest(undefined);}
        if(accepted&&current&&!signal.aborted&&standardMounted.current)resolve(undefined);
        else reject(Error('Synthetic confirmation cancelled'));
      };
      const abort=()=>finish(false);
      const entry:StandardLabRequest=Object.freeze({intent,signal,complete:()=>finish(true),cancel:()=>finish(false)});
      standardPending.current=entry;signal.addEventListener('abort',abort,{once:true});
      if(signal.aborted||!standardMounted.current)finish(false);else setStandardRequest(entry);
    });
  }

  const [state,setState] = useState<LabState | undefined>();
  const [action,setAction] = useState<TradeAction>('list');
  const [nft,setNft] = useState(''); const [contract,setContract] = useState('');
  const [amount,setAmount] = useState('10'); const [busy,setBusy] = useState(false);
  const [status,setStatus] = useState('Loading synthetic account');
  const [ready,setReady] = useState<ReviewedIntent | undefined>();
  const [continuation,setContinuation] = useState<Continuation | undefined>();
  const [watchOnly,setWatchOnly] = useState(false);
  const [pendingCount,setPendingCount] = useState(0);
  const [adverts,setAdverts] = useState<readonly AdvertisedOffer[] | 'loading' | 'unavailable' | undefined>();
  const advertRequest = useRef<AbortController | undefined>();
  const session = useRef<TradingSession | undefined>();
  const generation = useRef(0); const captured = useRef<ReviewedIntent | undefined>();
  const recoveryRequest = useRef<AbortController | undefined>();
  const journal = useRef<PendingJournal | undefined>();
  const displayedContext = useRef<{account:string;chain:'-239'} | undefined>();
  const pendingRead = useRef(0);
  const pageSuspended = useRef(false);
  const [marketFresh,setMarketFresh] = useState(false);
  const marketReady = useRef(false);
  const policy = useRef<Awaited<ReturnType<typeof createLabPolicy>> | undefined>();
  const policyRevision = useRef('');
  const [shownPolicyRevision,setShownPolicyRevision] = useState('');
  const initialBrand = 'mytonwallet' as SyntheticBrand;
  const brand = state?.brand ?? initialBrand;
  const selectedBrand = useRef(initialBrand);
  const currentGift=state?.gifts.find(g=>g.address===nft);
  const choices=state?.listings.filter(listing=>listing.nft===nft
    && listingMatchesAction(listing,currentGift,state.account,action)) ?? [];
  const canReview=contract ? choices.some(listing=>listing.contract===contract) : action==='list'||action==='make-offer';
  async function refreshPending() {
    const context=displayedContext.current, source=journal.current, token=++pendingRead.current!;
    if(!context||!source)return;
    try {
      const rows=await boundedRead(new AbortController().signal,()=>source.list(context));
      if(token===pendingRead.current&&context===displayedContext.current)
        setPendingCount(rows.filter(r=>['uncertain','submitted'].includes(r.state)).length);
    } catch {
      // Keep the last known count. A failed read is not evidence of an empty journal.
      if(token===pendingRead.current&&context===displayedContext.current)setPendingCount(-1);
    }
  }
  function clearAdverts() {
    advertRequest.current?.abort();
    advertRequest.current=undefined;
    setAdverts(undefined);
  }
  function cancel() { generation.current! += 1; recoveryRequest.current?.abort();session.current?.cancel(); clearAdverts();setReady(undefined); setContinuation(undefined); setBusy(false); captured.current=undefined; }
  async function loadAdverts() {
    if(!state||!currentGift||!marketReady.current||pageSuspended.current||advertRequest.current)return;
    const controller=new AbortController();
    advertRequest.current=controller;
    setAdverts('loading');
    try {
      const rows=await readAdvertisedOffers((path,signal)=>request('advertised-offers',{path},signal),value=>value,
        {chain:state.chain,nft:currentGift.address,collection:state.giftProfile.collection,traits:{}},
        controller.signal,()=>Math.floor(Date.now()/1000));
      if(advertRequest.current===controller)setAdverts(rows);
    } catch {
      if(advertRequest.current===controller)setAdverts('unavailable');
    } finally {
      if(advertRequest.current===controller)advertRequest.current=undefined;
    }
  }
  useEffect(()=>{
    if(!adverts||typeof adverts==='string'||!adverts.length)return undefined;
    const expires=Math.min(...adverts.map(offer=>offer.expiresAt));
    const timer=setTimeout(()=>{
      setAdverts(current=>current===adverts?adverts.filter(offer=>offer.expiresAt>Math.floor(Date.now()/1000)):current);
    },Math.max(0,Math.min(2147483647,expires*1000-Date.now())));
    return ()=>clearTimeout(timer);
  },[adverts]);
  function beginRead(){
    recoveryRequest.current?.abort();
    const controller=new AbortController();
    recoveryRequest.current=controller;
    return controller;
  }
  async function reload(successStatus = 'Ready — local emulator only') {
    if(pageSuspended.current)return;
    clearAdverts();
    const token = ++generation.current!; session.current?.cancel(); setReady(undefined);setContinuation(undefined);
    const controller=beginRead();
    marketReady.current=false;setMarketFresh(false);setBusy(true);
    const selected=selectedBrand.current;
    displayedContext.current={account:syntheticAccounts[selected],chain:'-239'};
    void refreshPending();
    try {
      const next = decodeLabState(await request('state',{brand:selected},controller.signal));
      if(token!==generation.current)return;
      if(next.brand!==selected||next.account!==syntheticAccounts[selected]||next.chain!=='-239')throw Error('Unexpected synthetic account');
      setState(next); if(!nft)setNft(next.gifts.find(g=>g.owner===next.account)?.address ?? next.gifts[0]?.address ?? '');
      await refreshPending();
      if(token!==generation.current)return;
      marketReady.current=true;setMarketFresh(true);setStatus(successStatus);
    } catch { if(token===generation.current)setStatus('Local source unavailable. Refresh before reviewing a trade.'); }
    finally{if(recoveryRequest.current===controller)recoveryRequest.current=undefined;if(token===generation.current)setBusy(false);}
  }
  useEffect(()=>{
    let disposed=false;
    const bootstrap=new AbortController();
    journal.current=new PendingJournal(indexedDbJournal(indexedDB,'gift-trading-lab-mytonwallet'));
    displayedContext.current={account:syntheticAccounts[initialBrand],chain:'-239'};
    void refreshPending();
    let channel:BroadcastChannel|undefined;
    try {channel=new BroadcastChannel('gift-trading-lab-mytonwallet');} catch { /* IndexedDB still coordinates reservations. */ }
    if(channel)channel.onmessage=event=>{if(event.data==='journal-changed')void refreshPending();};
    const refreshOnFocus=()=>{void refreshPending();};
    let policyReady=false;
    function suspendPage(){
      pageSuspended.current=true;
      cancel();
      setBusy(true);
      setStatus('Page left. Pending operations remain recorded.');
    }
    function restorePage(){
      if(!pageSuspended.current)return;
      pageSuspended.current=false;
      if(policyReady)void reload();
      else setBusy(false);
    }
    window.addEventListener('focus',refreshOnFocus);
    window.addEventListener('pagehide',suspendPage);
    window.addEventListener('pageshow',restorePage);
    const unsubscribe=journal.current.subscribe(()=>{
      void refreshPending();
      channel?.postMessage('journal-changed');
    });
    void createLabPolicy(bootstrap.signal).then(async p=>{
      if(disposed){p.close();return;}policy.current=p;
      const current=await p.policy.current();if(disposed)return;
      policyReady=true;policyRevision.current=String(current.revision);setShownPolicyRevision(String(current.revision));await reload();
    }).catch(()=>{if(disposed)return;policy.current?.close();policy.current=undefined;setStatus('Local policy unavailable. No operation is permitted.');});
    return()=>{
      disposed=true;bootstrap.abort();recoveryRequest.current?.abort();advertRequest.current?.abort();
      advertRequest.current=undefined;unsubscribe();channel?.close();
      window.removeEventListener('focus',refreshOnFocus);
      window.removeEventListener('pagehide',suspendPage);
      window.removeEventListener('pageshow',restorePage);
      displayedContext.current=undefined;pendingRead.current!+=1;generation.current!+=1;
      session.current?.cancel();policy.current?.close();policy.current=undefined;
    };
  },[]);
  async function checkProfile(current:LabState,kind:'new'|'recovery'='new') {
    const p=policy.current;if(!p)throw Error('Policy unavailable');
    if(current.giftProfile.id!==p.profile.id||current.giftProfile.codeHash!==p.profile.codeHash||current.giftProfile.collection!==p.profile.collection)throw Error('Unexpected local profile');
    const checked=await p.policy.current();
    const scope={chain:current.chain,collection:p.profile.collection,environment:'laboratory'} as const;
    if(kind==='recovery')await checked.registry.allowRecovery(p.profile.id,p.profile.codeHash,scope);
    else await checked.registry.allowNew(p.profile.id,p.profile.codeHash,scope);
    return checked;
  }
  async function changePolicy(revision:2|3) {
    cancel();const token=++generation.current!;setBusy(true);
    try {
      const p=policy.current;if(!p)throw Error('Policy unavailable');await p.install(revision);
      const current=await p.policy.current();if(token!==generation.current)return;
      policyRevision.current=String(current.revision);setShownPolicyRevision(String(current.revision));
      setStatus(revision===2?'Test profile revoked. New confirmations are disabled.':'Test profile restored. Prepare a new review.');
    } catch {if(token===generation.current)setStatus('Policy update rejected. No operation was sent.');}
    finally {if(token===generation.current)setBusy(false);}
  }
  async function prepare() {
    if(!state||!canReview||!marketReady.current||pageSuspended.current)return;cancel();const token=++generation.current!;setBusy(true);setStatus('Verifying local state');
    try {
      const current=await checkProfile(state);if(token!==generation.current)return;
      policyRevision.current=String(current.revision);setShownPolicyRevision(String(current.revision));
      const boundary=policy.current!.boundary;
      const listing=choices.find(item=>item.contract===contract);
      const price=listing?.price??parseTonInput(amount);
      const instance=new TradingSession({account:state.account,chain:state.chain},{
        resolve:async(selected,_context,signal)=>{
          const reply=await request('prepare',{brand,action:selected,nft,contract:contract||undefined,price},signal);
          return decodeLabPreparation(reply,{action:selected,nft,price,listing});
        },
        verify:async(intent,signal)=>{
          const reply=await request('verify',{brand,id:intent.id},signal);
          return decodeLabVerification(reply,intent,Math.floor(Date.now()/1000));
        },
        accountKind:()=>watchOnly?'watch-only':'software',policyRevision:()=>policyRevision.current!,
        beforeCapture:async(intent,signal)=>{await checkProfile(state);await requestStandardConfirmation(intent,signal);return undefined;},
        withConfirmationPolicy:(revision,signal,work)=>boundary.run(revision,signal,work),
        capture:intent=>{captured.current=intent;return undefined;},
      },journal.current!,()=>Math.floor(Date.now()/1000));
      session.current=instance;const intent=await instance.prepare(action);
      if(token!==generation.current)return;
      setReady(intent);setStatus('Review the exact operation');
    } catch {if(token===generation.current)setStatus('Cannot prepare: check owner, amount, listing, account mode and current state.');}
    finally {if(token===generation.current)setBusy(false);}
  }
  async function confirm() {
    if(!ready||!session.current||!state||pageSuspended.current)return;const token=generation.current;setBusy(true);setReady(undefined);setStatus('Rechecking and recording pending operation');
    const context={account:state.account,chain:state.chain};
    let requested=false;
    let controller:AbortController|undefined;
    try {
      await session.current.confirm(ready);
      if(token!==generation.current||captured.current!==ready)throw Error('Cancelled confirmation');
      // This endpoint executes only in-memory TON emulator messages. It cannot sign or broadcast.
      controller=beginRead();
      requested=true;
      const result=decodeLabReceipt(await request('execute',{brand,id:ready.id},controller.signal));
      if(token!==generation.current)return;
      const action=ready.review.action;
      const stage=action==='list'?(ready.plan.messages[0]?.stateInit?'deploy':'deposit')
        :action==='make-offer'?'offer-funding':'operation';
      if(!matchesLabReceipt(result,{...context,id:ready.id,action},stage))throw Error('Receipt does not match this operation');
      if(result.outcome==='pending'&&result.status==='awaiting-proof'){
        await reload('Awaiting delivery proof. Observed gift owner: '+(result.observedOwner??'unknown')+'. Reconcile without resending.');
        return;
      }
      if(result.outcome!=='confirmed')throw Error('Operation remains unconfirmed');
      await journal.current!.reconcile(context,ready.id,'settled',result.messageHash,Math.floor(Date.now()/1000));
      if(token!==generation.current)return;
      await reload(result.stage==='deploy'?'Sale contract prepared in emulator. Select it and review the separate gift deposit.':'Operation completed in local emulator. No real assets moved.');
    } catch {
      if(token===generation.current) {
        try {
          const rows=await boundedRead(new AbortController().signal,()=>journal.current!.list(context));
          if(token!==generation.current)return;
          const own=rows.find(row=>row.intentId===ready.id);
          const pending=rows.filter(r=>['uncertain','submitted'].includes(r.state)).length;
          void refreshPending();
          if(own?.state==='settled')setStatus('This operation was already reconciled.');
          else if(requested)setStatus('Result is uncertain. Reconcile the pending operation before retrying.');
          else if(pending>0)setStatus('This confirmation did not send an operation. Reconcile the pending operation first.');
          else setStatus('Operation was not sent. Review again before retrying.');
        } catch {if(token===generation.current)setStatus('Cannot verify pending operations. Do not retry until the journal is available.');}
      }
    }
    finally {if(controller&&recoveryRequest.current===controller)recoveryRequest.current=undefined;if(token===generation.current)setBusy(false);}
  }
  async function reconcile() {
    const context=displayedContext.current;
    if(!context||pageSuspended.current)return;
    cancel();const token=++generation.current!, controller=beginRead();
    setBusy(true);setStatus('Checking previous operation; no resend');
    try {
      const rows=await boundedRead(controller.signal,()=>journal.current!.list(context));
      const unresolved=new Set<string>();
      for(const row of rows.filter(r=>['uncertain','submitted'].includes(r.state))){
        const result=decodeLabReceipt(await request('reconcile',{brand:selectedBrand.current,id:row.intentId},controller.signal));
        if(token!==generation.current)return;
        const matched=result?.found&&matchesLabReceipt(result,{...context,id:row.intentId,action:row.action});
        if(matched&&result.outcome==='confirmed'){
          await journal.current!.reconcile(context,row.intentId,'settled',result.messageHash,Math.floor(Date.now()/1000));
        }else if(matched
            &&['awaiting-proof','awaiting-continuation','awaiting-credit','partial-credit'].includes(result.status)){
          unresolved.add(result.status);
        }else{
          unresolved.add('unknown');
        }
      }
      if(token!==generation.current)return;
      if(!unresolved.size){await reload();return;}
      const details=[
        unresolved.has('unknown')?'Previous result remains unknown.':'',
        unresolved.has('awaiting-proof')?'Awaiting delivery proof.':'',
        unresolved.has('awaiting-continuation')?'Settlement needs another reviewed step.':'',
        unresolved.has('awaiting-credit')?'Awaiting confirmation of recipient credit.':'',
        unresolved.has('partial-credit')?'Only some recipients have confirmed credit.':'',
      ].filter(Boolean);
      await reload(details.join(' ')+' Nothing was resent.');
    }catch{if(token===generation.current)setStatus('Status unavailable. Pending operations remain recorded.');}
    finally{if(recoveryRequest.current===controller)recoveryRequest.current=undefined;if(token===generation.current)setBusy(false);}
  }
  async function reviewContinuation() {
    if(!state||watchOnly||pageSuspended.current)return;
    cancel();const token=++generation.current!, controller=beginRead();setBusy(true);
    try {
      const context={account:state.account,chain:state.chain};
      const checked=await checkProfile(state,'recovery');
      if(token!==generation.current)return;
      const rows=await boundedRead(controller.signal,()=>journal.current!.list(context));
      for(const row of rows.filter(r=>['uncertain','submitted'].includes(r.state))){
        if(token!==generation.current)return;
        const ref=decodeReference(row.reference,context.chain);
        const reply=await request('review-continuation',{brand,id:row.intentId},controller.signal);
        const review=await decodeLabContinuation(reply,{...context,id:row.intentId,nft:ref.nft,market:ref.contract},
          Math.floor(Date.now()/1000));
        if(token!==generation.current)return;
        if(!review)continue;
        setContinuation({...review,policyRevision:String(checked.revision),action:row.action});setStatus('Review the next step before continuing.');return;
      }
      if(token===generation.current)setStatus('No continuation is available. Pending results remain recorded.');
    }catch{if(token===generation.current)setStatus('Cannot review a continuation. No operation was sent.');}
    finally{if(recoveryRequest.current===controller)recoveryRequest.current=undefined;if(token===generation.current)setBusy(false);}
  }
  async function resume() {
    if(!state||!continuation||watchOnly||busy||pageSuspended.current)return;
    const token=++generation.current!;const review=continuation;
    const controller=beginRead();
    setContinuation(undefined);setBusy(true);
    const context={account:state.account,chain:state.chain};
    const lockName='gift-continuation-mytonwallet-'+review.id;
    try {
      const outcome=await boundedRead(controller.signal,async signal=>{
        const continued=await navigator.locks.request(lockName,{mode:'exclusive',ifAvailable:true},async lock=>{
          if(!lock)return false as const;
          signal.throwIfAborted();
          const entry=(await boundedRead(signal,()=>journal.current!.list(context))).find(row=>row.intentId===review.id);
          signal.throwIfAborted();
          if(token!==generation.current||entry?.action!==review.action)throw Error('Recovery review changed');
          if(entry.state==='settled')return undefined;
          if(entry.state!=='uncertain'&&entry.state!=='submitted')throw Error('Recovery result is already recorded');
          let result:LabReceipt | undefined;
          await policy.current!.boundary.run(review.policyRevision,signal,async guard=>{
            const checked=await checkProfile(state,'recovery');
            guard();
            if(token!==generation.current||String(checked.revision)!==review.policyRevision)throw Error('Recovery review changed');
            if(review.expiresAt<=Math.floor(Date.now()/1000))throw Error('Continuation expired');
            result=decodeLabReceipt(await request('resume',{brand,id:review.id,expiresAt:review.expiresAt,reviewHash:review.reviewHash},signal));
          });
          signal.throwIfAborted();
          if(token!==generation.current||!result?.found||!matchesLabReceipt(result,{...context,id:review.id,action:review.action},'operation')){
            throw Error('Continuation receipt does not match this operation');
          }
          if(result.outcome==='confirmed'){
            const messageHash=result.messageHash;
            await boundedRead(signal,()=>journal.current!.reconcile(context,review.id,'settled',messageHash,Math.floor(Date.now()/1000)));
            return undefined;
          }
          if(result.status==='awaiting-continuation')return 'Settlement needs another reviewed step.';
          if(result.status==='partial-credit')return 'Only some recipients have confirmed credit.';
          if(result.status==='awaiting-credit')return 'Awaiting confirmation of recipient credit.';
          throw Error('Continuation result is unconfirmed');
        });
        if(continued!==false)return continued;
        // The other tab owns this attempt. After it releases the lock, only read
        // the result. A stale click cannot automatically start another continuation.
        await navigator.locks.request(lockName,{mode:'shared',signal},()=>undefined);
        return null;
      },30000);
      if(token!==generation.current)return;
      if(outcome===null){await reconcile();return;}
      await reload(outcome);
    }catch{if(token===generation.current)setStatus('Continuation result unavailable. Check status before preparing another step.');}
    finally{if(recoveryRequest.current===controller)recoveryRequest.current=undefined;if(token===generation.current)setBusy(false);}
  }
  function changeAction(event: any) {cancel();setAction(event.target.value as TradeAction);setContract('');}
  return <section className="gift-trading-lab" aria-label="Gift trading local test">
    {onClose&&<button type="button" onClick={()=>{cancel();onClose();}}>Back to gifts</button>}
    <header><h1>Gift marketplace · MyTonWallet</h1><p>LOCAL EMULATOR · Synthetic gifts · No wallet connection, signing or network transactions</p></header>
    <p role="status" aria-live="polite">{status}</p>
    <p>Laboratory policy revision: <span data-testid="policy-revision">{shownPolicyRevision}</span></p>
    <div><button type="button" disabled={busy||!state||Number(shownPolicyRevision)>=2} onClick={()=>void changePolicy(2)}>Revoke test profile</button><button type="button" disabled={busy||!state||Number(shownPolicyRevision)>=3} onClick={()=>void changePolicy(3)}>Restore test profile</button></div>
    <p>Pending operations: <strong data-testid="pending-count">{pendingCount<0?'Unknown':pendingCount}</strong>. Unknown results must be reconciled; restarting does not resend.</p>
    {pendingCount!==0&&<button type="button" disabled={busy} onClick={()=>void reconcile()}>Reconcile previous operation</button>}
    {pendingCount>0&&<button type="button" disabled={busy||watchOnly} onClick={()=>void reviewContinuation()}>Review continuation</button>}
    {continuation&&<div className="gift-trading-review" aria-label="Continuation review">
      <h2>Confirm next emulator step</h2>
      <dl><dt>Step</dt><dd>{continuation.step}</dd><dt>Gift</dt><dd>{continuation.nft}</dd>
        <dt>Market contract</dt><dd>{continuation.market}</dd><dt>Query</dt><dd>{continuation.query}</dd>
        <dt>Expected owner</dt><dd>{continuation.expectedOwner}</dd>
        <dt>Network</dt><dd>{continuation.chain}</dd><dt>Account</dt><dd>{continuation.account}</dd>
        <dt>Review expires</dt><dd>{new Date(continuation.expiresAt*1000).toISOString()}</dd>
        <dt>Synthetic contribution</dt><dd>{formatTon(continuation.contribution)} TON</dd></dl>
      {continuation.payouts.map((p,index)=>{
        const role=payoutRole(continuation.step,index);
        return <p key={role}>{role}: {formatTon(p.amount)} TON → {p.recipient}</p>;
      })}
      <button type="button" disabled={busy||watchOnly} onClick={()=>void resume()}>Continue in emulator</button>
    </div>}
    <div className="gift-trading-form">
      <label>Synthetic account<select aria-label="Synthetic account" value={brand} onChange={(event:any)=>{
        const next=event.target.value;
        if(next!=='mytonwallet'&&next!=='tonkeeper')return;
        cancel();selectedBrand.current=next;displayedContext.current=undefined;pendingRead.current!+=1;
        setState(undefined);setPendingCount(0);setNft('');setContract('');setStatus('Loading synthetic account');void reload();
      }}><option value="mytonwallet">MyTonWallet test account</option><option value="tonkeeper">Tonkeeper test account</option></select></label>
      <label>Action<select aria-label="Action" value={action} onChange={changeAction}>{actions.map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label>
      <label>Gift<select aria-label="Gift" value={nft} onChange={(event:any)=>{cancel();setNft(event.target.value);setContract('');}}>{state?.gifts.map(g=><option key={g.address} value={g.address}>{giftLabel(g.title)}</option>)}</select></label>
      <label>Listing or offer<select aria-label="Listing or offer" value={contract||'new'} onChange={(event:any)=>{cancel();setContract(event.target.value==='new'?'':event.target.value);}}><option value="new">New / select existing</option>{choices.map(l=><option key={l.contract} value={l.contract}>{l.kind} · {formatTon(l.price)} TON · {listingStatus(l)} · {l.contract.slice(-8)}</option>)}</select></label>
      <label>Price, TON<input aria-label="Price, TON" inputMode="decimal" maxLength={38} value={amount} onInput={(event:any)=>{cancel();setAmount(event.target.value);}} /></label>
    </div>
    <label><input type="checkbox" checked={watchOnly} onChange={()=>{cancel();setWatchOnly(!watchOnly);}} /> Watch-only test account (confirmation disabled)</label>
    <dl><dt>Synthetic account</dt><dd>{state?.account ?? 'Loading'}</dd><dt>Gift address</dt><dd>{nft}</dd><dt>Current owner</dt><dd>{currentGift?.owner}</dd></dl>
    <div className="gift-trading-buttons"><button type="button" disabled={busy||!shownPolicyRevision} onClick={()=>void reload()}>Refresh market</button><button type="button" disabled={busy||!marketFresh||watchOnly||!canReview} onClick={()=>void prepare()}>Prepare review</button><button type="button" onClick={()=>{cancel();setStatus('Review cancelled. Nothing will be confirmed automatically.');}}>Cancel review</button></div>
    {ready&&<div className="gift-trading-review" aria-label="Trade review"><h2>Confirm local simulation</h2>
      <dl><dt>Action</dt><dd>{ready.review.action}</dd><dt>Provider</dt><dd>{ready.review.provider}</dd><dt>Price</dt><dd>{formatTon(ready.review.amount)} TON</dd><dt>Included royalty</dt><dd>{formatTon(ready.review.royalty)} TON</dd><dt>Fee reserve</dt><dd>{formatTon(ready.review.gasBudget)} TON — laboratory estimate</dd><dt>Counterparty</dt><dd>{ready.review.counterparty}</dd><dt>Market contract</dt><dd>{ready.review.reference.contract}</dd><dt>Gift</dt><dd>{ready.review.reference.nft}</dd><dt>Network</dt><dd>{ready.review.context.chain}</dd><dt>Review expires</dt><dd>{new Date(ready.review.expiresAt*1000).toISOString()}</dd></dl>
      {ready.plan.messages.map((m,i)=><p key={i}>Message {i+1}: {formatTon(m.amount)} TON → {m.to}</p>)}
      <p>Experimental gas reserve rules. This is not a production quote.</p>
      <button type="button" disabled={busy||watchOnly} onClick={()=>void confirm()}>Confirm in emulator</button>
    </div>}
    {standardRequest&&<MyTonWalletStandardConfirmation key={standardRequest.intent.id} request={standardRequest} />}
    <section aria-label="Getgems test offers">
      <h2>Getgems test offers</h2>
      <button type="button" disabled={!marketFresh||!currentGift||adverts==='loading'} onClick={()=>void loadAdverts()}>Load test offers</button>
      {adverts&&<p aria-live="polite">{adverts==='loading'?'Loading test offers':adverts==='unavailable'?'Test offers unavailable':
        adverts.length?'Advertised terms only. Funding unverified. Network fee unknown.':'No matching test offers'}</p>}
      {adverts&&typeof adverts!=='string'&&adverts.length>0&&<ul aria-label="Advertised Getgems offers">
        {adverts.map(offer=><li key={offer.id}>{offer.scope==='nft'?'Gift offer':'Collection offer'}
          {' · '}{formatTon(offer.gross)} TON offered · {formatTon(offer.netBeforeNetworkFee)} TON before network fees
          {' · Expires '}{new Date(offer.expiresAt*1000).toISOString()}</li>)}
      </ul>}
    </section>
    <h2>Shared market</h2><p>These are the same local listings for both wallets. Production market discovery is disabled.</p>
    <ul aria-label="Shared market">{state?.listings.map(l=>{
      const next=marketAction(l,state.gifts.find(g=>g.address===l.nft),state.account);
      const label=l.kind+' · '+formatTon(l.price)+' TON · '+listingStatus(l);
      return <li key={l.contract}>{next
        ? <button type="button" disabled={!marketFresh||busy||watchOnly} onClick={()=>{cancel();setNft(l.nft);setContract(l.contract);setAction(next);}}>{label}</button>
        : <span>{label}</span>}<code>{l.reference}</code></li>;
    })}</ul>
  </section>;
}
