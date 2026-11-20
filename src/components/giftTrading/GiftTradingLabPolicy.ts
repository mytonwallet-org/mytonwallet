import { AuthenticatedProfilePolicy, IndexedDbPolicyStore } from '../../api/giftTrading/profile-policy';
import type { SignedPolicy } from '../../api/giftTrading/profile-policy';
import { LockedPolicyStore, ConfirmationPolicyBoundary } from '../../api/giftTrading/policy-boundary';
import { boundedRead } from '../../api/giftTrading/bounded';
// Pinned at local build time. This test authority has no production rights.
const config = {"scope":"Synthetic build-only policy; never a production trust root","publicKey":[4,121,219,24,153,191,48,103,123,141,130,23,137,79,142,201,132,81,240,243,250,58,247,247,85,126,129,77,207,152,189,150,108,100,237,99,13,78,213,159,33,101,226,33,133,220,205,56,151,134,208,29,6,231,136,94,21,45,93,113,120,47,33,78,182],"profile":{"id":"standard-nft-laboratory","codeHash":"4c9123828682fa6f43797ab41732bca890cae01766e0674100250516e0bf8d42","collection":"0:b98d823fe3cf1afe7e791d51e8b367a8aa92e247bab6a417c80ba453e276ab19"},"fixtures":[{"keyId":"local-build","payload":"{\"version\":1,\"revision\":1,\"chain\":\"-239\",\"environment\":\"laboratory\",\"issuedAt\":1794606405,\"expiresAt\":1794779205,\"profiles\":[{\"id\":\"standard-nft-laboratory\",\"codeHash\":\"4c9123828682fa6f43797ab41732bca890cae01766e0674100250516e0bf8d42\",\"layout\":\"standard-nft-v1\",\"chain\":\"-239\",\"collections\":[\"0:b98d823fe3cf1afe7e791d51e8b367a8aa92e247bab6a417c80ba453e276ab19\"],\"immutable\":true,\"authenticatedAck\":true,\"environment\":\"laboratory\",\"enabled\":true,\"recoveryReviewed\":true}]}","signature":"5983b275beecb19cabbd76ff9a40dc3989083100516e45ad03715c87aac02b2e1c10203db098ca79945952c7fe0ebed9e84b089ec4a3812d2beacb2c542c049e"},{"keyId":"local-build","payload":"{\"version\":1,\"revision\":2,\"chain\":\"-239\",\"environment\":\"laboratory\",\"issuedAt\":1794606405,\"expiresAt\":1794779205,\"profiles\":[{\"id\":\"standard-nft-laboratory\",\"codeHash\":\"4c9123828682fa6f43797ab41732bca890cae01766e0674100250516e0bf8d42\",\"layout\":\"standard-nft-v1\",\"chain\":\"-239\",\"collections\":[\"0:b98d823fe3cf1afe7e791d51e8b367a8aa92e247bab6a417c80ba453e276ab19\"],\"immutable\":true,\"authenticatedAck\":true,\"environment\":\"laboratory\",\"enabled\":false,\"recoveryReviewed\":true}]}","signature":"b8f8d523eddd6b8c1a502cfc1527e3beb3adb3c1f3a71a6d2b3960c98b4f7272d90dbb35db25e6416cfe39dee297f3bddba26cff6735f3784d20ba3d68aa2026"},{"keyId":"local-build","payload":"{\"version\":1,\"revision\":3,\"chain\":\"-239\",\"environment\":\"laboratory\",\"issuedAt\":1794606405,\"expiresAt\":1794779205,\"profiles\":[{\"id\":\"standard-nft-laboratory\",\"codeHash\":\"4c9123828682fa6f43797ab41732bca890cae01766e0674100250516e0bf8d42\",\"layout\":\"standard-nft-v1\",\"chain\":\"-239\",\"collections\":[\"0:b98d823fe3cf1afe7e791d51e8b367a8aa92e247bab6a417c80ba453e276ab19\"],\"immutable\":true,\"authenticatedAck\":true,\"environment\":\"laboratory\",\"enabled\":true,\"recoveryReviewed\":true}]}","signature":"d73786d8cea282b0d5fe7f591f392dd74b64df4c3edb8fc26ab6eb18ad597988667f38cc62cc704a73cd990a81954a4b7c297134f66ab3e30178826043310c17"}],"issuedAt":1794606405,"expiresAt":1794779205,"privateKeyPersisted":false};
export async function createLabPolicy(signal:AbortSignal) {
  signal.throwIfAborted();
  const db = await new Promise<IDBDatabase>((resolve,reject)=>{
    let expired=false;
    const stop=()=>{expired=true;clearTimeout(timer);signal.removeEventListener('abort',stop);reject(Error('Policy bootstrap cancelled'));};
    const timer=setTimeout(stop,10000);signal.addEventListener('abort',stop,{once:true});
    const r=indexedDB.open('gift-trading-policy-mytonwallet',1);
    r.onupgradeneeded=()=>r.result.createObjectStore('gift-policy');
    r.onsuccess=()=>{clearTimeout(timer);signal.removeEventListener('abort',stop);if(expired||signal.aborted)r.result.close();else resolve(r.result);};
    r.onerror=()=>{clearTimeout(timer);signal.removeEventListener('abort',stop);reject(Error('Policy database unavailable'));};
    r.onblocked=stop;
  });
  try {
    const clock=()=>Math.floor(Date.now()/1000);
    const store=new LockedPolicyStore(new IndexedDbPolicyStore(db),navigator.locks,'lab-mytonwallet');
    const policy=new AuthenticatedProfilePolicy(store,{keys:{'local-build':new Uint8Array(config.publicKey)},chain:'-239',environment:'laboratory',minimumRevision:1},clock);
    // Never reset or overwrite existing evidence (including corrupt/expired policy).
    await boundedRead(signal,async scoped=>{
      if(await store.read()===null){scoped.throwIfAborted();await policy.install(config.fixtures[0]! as SignedPolicy);}
      scoped.throwIfAborted();await policy.current();scoped.throwIfAborted();
    });
    return {policy,boundary:new ConfirmationPolicyBoundary(store,policy,clock),profile:config.profile,
      install:async(revision:2|3)=>policy.install(config.fixtures[revision-1]! as SignedPolicy),close:()=>db.close()};
  } catch(error) {db.close();throw error;}
}
