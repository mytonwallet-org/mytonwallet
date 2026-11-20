import React, { useState } from '../../lib/teact/teact';
import { TONCOIN } from '../../config';
import { TransferConfirmForLaboratory } from '../transfer/TransferConfirm';
import { PasswordFormForLaboratory } from '../ui/PasswordForm';
import type { ReviewedIntent } from '../../api/giftTrading/intent';
import type { GlobalState } from '../../global/types';

export type StandardLabRequest = Readonly<{intent:ReviewedIntent;signal:AbortSignal;complete:()=>void;cancel:()=>void}>;
/** Real wallet review/form components, strictly synthetic authorization. No signer. */
export default function MyTonWalletStandardConfirmation({request}:{request:StandardLabRequest}) {
  const [step,setStep]=useState(0),[authorizing,setAuthorizing]=useState(false),[delay,setDelay]=useState(false);
  const messages=request.intent.plan.messages,message=messages[step]!;
  const transfer={tokenSlug:TONCOIN.slug,amount:BigInt(message.amount),toAddress:message.to,resolvedAddress:message.to,
    ...(message.payload?{binPayload:message.payload}:{}),...(message.stateInit?{stateInit:message.stateInit}:{}),
    promiseId:'synthetic-'+request.intent.id,isLoading:false} as GlobalState['currentTransfer'];
  const authorize=async(password:string,signal:AbortSignal):Promise<undefined>=>{
    if(password!=='test')throw Error('Only the literal test is accepted');
    if(delay)await new Promise(resolve=>setTimeout(resolve,750));
    signal.throwIfAborted();request.signal.throwIfAborted();return undefined;
  };
  return <div className="gift-standard-confirmation" aria-label="Standard wallet confirmation test" style="background:white;color:black;padding:20px;border:2px solid #777;">
    <h2>Standard wallet screen · synthetic operation</h2>
    <p>Type only <strong>test</strong>. Never enter a real wallet password. This form cannot unlock keys or send transactions.</p>
    <p>Account: {request.intent.plan.account} · Network: {request.intent.plan.chain}</p>
    {!authorizing?<>
      <p>Message {step+1} of {messages.length}</p>
      <p>Exact message target: <code data-testid="exact-recipient">{message.to}</code></p>
      <div data-testid="standard-native-review"><TransferConfirmForLaboratory isActive currentAccountId="synthetic-account" currentTransfer={transfer}
        accounts={{}} token={{...TONCOIN,name:'Synthetic TON',symbol:'TON'}} onClose={request.cancel} onBack={request.cancel}
        laboratoryConfirm={()=>{request.signal.throwIfAborted();if(step+1<messages.length)setStep(step+1);else setAuthorizing(true);}} /></div>
    </>:<>
      <label><input type="checkbox" checked={delay} onChange={()=>setDelay(!delay)} /> Delay synthetic authorization reply</label>
      <PasswordFormForLaboratory isActive placeholder="Type test (simulation only)" noAnimatedIcon
        submitLabel="Authorize synthetic operation" cancelLabel="Back" onCancel={request.cancel} onClose={request.cancel}
        laboratoryAuth={{authorize}} onAuthorize={(token:string)=>{if(token!=='lab-capture-only')throw Error('Unexpected synthetic token');request.signal.throwIfAborted();request.complete();}} />
    </>}
  </div>;
}
