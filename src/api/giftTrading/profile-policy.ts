import { ProfileRegistry } from './profiles.js';
import type { CompatibilityProfile, ProfileScope } from './profiles.js';
import { network, timestamp } from './protocol.js';
import type { Chain } from './protocol.js';
import { boundedRead } from './bounded.js';
import { boundedJson } from './privacy.js';

export type SignedPolicy = Readonly<{ keyId: string; payload: string; signature: string }>;
export type PolicyDocument = Readonly<{ version: 1; revision: number; chain: Chain;
  environment: 'laboratory' | 'production'; issuedAt: number; expiresAt: number;
  profiles: readonly CompatibilityProfile[] }>;
type VerifiedPolicy = { envelope: SignedPolicy; document: PolicyDocument; registry: ProfileRegistry };
export type PolicyCommit = Readonly<{ signal: AbortSignal; check: () => void }>;
/** Atomic compare-and-swap checks the write guard immediately before mutation,
 * reports durable commit, and aborts an uncommitted transaction on cancellation. */
export interface PolicyStore {
  read(): Promise<SignedPolicy | null>;
  compareAndSwap(expected: SignedPolicy | null, next: SignedPolicy, commit: PolicyCommit): Promise<boolean>;
}
export function samePolicy(a: SignedPolicy | null, b: SignedPolicy | null): boolean {
  return a === null ? b === null : b !== null && a.keyId === b.keyId && a.payload === b.payload && a.signature === b.signature;
}
function copyEnvelope(value: SignedPolicy): SignedPolicy {
  if (!value || typeof value.keyId !== 'string' || !/^[a-z0-9-]{1,64}$/.test(value.keyId)
    || typeof value.payload !== 'string' || value.payload.length > 131072
    || typeof value.signature !== 'string' || !/^[a-f0-9]{128}$/.test(value.signature)) throw Error('Invalid signed policy envelope');
  return Object.freeze({ keyId: value.keyId, payload: value.payload, signature: value.signature });
}
export function policySigningBytes(keyId: string, payload: string) {
  return new TextEncoder().encode(`wallet-gift-policy-v1\n${keyId}\n${payload}`);
}
/** Pinned public keys and minimum revision come from trusted wallet configuration, never NFT/API data.
 * Protects against replay across ordinary restarts. Full device/storage rollback or deletion requires
 * a fresh trusted checkpoint; IndexedDB alone cannot prove freshness after disk rollback.
 * This module does not download policies, provide production keys or enable production trading.
 */
export class AuthenticatedProfilePolicy {
  #keys: ReadonlyMap<string, ArrayBuffer>;
  #chain: Chain;
  #environment: 'laboratory' | 'production';
  #minimum: number;
  #observed?: Readonly<{ revision: number; keyId: string; payload: string }>;
  #read(): Promise<SignedPolicy | null> { return boundedRead(new AbortController().signal,()=>this.store.read()); }
  constructor(private readonly store: PolicyStore, trust: Readonly<{ keys: Readonly<Record<string, Uint8Array>>;
    chain: Chain; environment: 'laboratory' | 'production'; minimumRevision: number }>, private readonly clock: () => number) {
    this.#chain = network(trust.chain); this.#environment = trust.environment; this.#minimum = trust.minimumRevision;
    if (!['laboratory','production'].includes(this.#environment) || !Number.isSafeInteger(this.#minimum) || this.#minimum < 0
      || Object.keys(trust.keys).length < 1 || Object.keys(trust.keys).length > 8) throw Error('Invalid policy trust configuration');
    this.#keys = new Map(Object.entries(trust.keys).map(([id,key]) => {
      if (!/^[a-z0-9-]{1,64}$/.test(id) || !(key instanceof Uint8Array) || key.length !== 65 || key[0] !== 4) throw Error('Invalid policy public key');
      return [id, new Uint8Array(key).buffer];
    }));
  }
  async #verify(value: SignedPolicy, requireFresh: boolean): Promise<VerifiedPolicy> {
    const envelope = copyEnvelope(value), rawKey = this.#keys.get(envelope.keyId);
    if (!rawKey) throw Error('Untrusted policy key');
    const key = await crypto.subtle.importKey('raw', rawKey, { name:'ECDSA', namedCurve:'P-256' }, false, ['verify']);
    const signature = Uint8Array.from(envelope.signature.match(/../g)!, h => parseInt(h,16));
    if (!await crypto.subtle.verify({ name:'ECDSA', hash:'SHA-256' }, key, signature, policySigningBytes(envelope.keyId,envelope.payload))) throw Error('Policy signature mismatch');
    const p = boundedJson(envelope.payload) as PolicyDocument;
    if (!p || p.version !== 1 || !Number.isSafeInteger(p.revision) || p.revision < 0 || (requireFresh && p.revision < this.#minimum) || p.chain !== this.#chain
      || p.environment !== this.#environment || !Array.isArray(p.profiles)) throw Error('Invalid policy scope or checkpoint');
    timestamp(p.issuedAt); timestamp(p.expiresAt);
    if (p.expiresAt <= p.issuedAt || p.expiresAt - p.issuedAt > 7 * 86400) throw Error('Invalid policy lifetime');
    const now = timestamp(this.clock());
    if (requireFresh && (p.issuedAt > now || now >= p.expiresAt)) throw Error('Policy is not current');
    const registry = new ProfileRegistry(); registry.install(p.revision,p.profiles);
    if (p.profiles.some(profile => profile.chain !== p.chain || profile.environment !== p.environment)) throw Error('Mixed policy scope');
    // Only this detached, authenticated registry is exposed. Its profiles are frozen by install().
    return { envelope, document:p, registry };
  }
  #checkObserved({ document, envelope }: VerifiedPolicy): void {
    const observed = this.#observed;
    if (!observed) return;
    if (document.revision < observed.revision) throw Error('Observed policy rollback');
    if (document.revision === observed.revision &&
      (envelope.keyId !== observed.keyId || envelope.payload !== observed.payload)) throw Error('Conflicting policy revision');
  }
  #rememberPersisted(verified: VerifiedPolicy): void {
    const { document, envelope } = verified;
    if (this.#observed && document.revision < this.#observed.revision) return;
    this.#checkObserved(verified);
    this.#observed = { revision:document.revision, keyId:envelope.keyId, payload:envelope.payload };
  }
  async install(value: SignedPolicy): Promise<void> {
    const incoming = await this.#verify(value,true);
    const checkTime = () => { const now = timestamp(this.clock());
      if (now < incoming.document.issuedAt || now >= incoming.document.expiresAt) throw Error('Policy expired during installation'); };
    for (let attempt = 0; attempt < 8; attempt++) {
      const stored = await this.#read();
      // Expired persisted policies still establish a floor. Only a verified
      // document read from storage or durably committed can advance it.
      const previous = stored === null ? undefined : await this.#verify(stored,false);
      if (previous) this.#rememberPersisted(previous);
      this.#checkObserved(incoming);
      // Storage or cryptographic waits cannot extend the validity of an expired policy.
      checkTime();
      if (previous?.document.revision === incoming.document.revision) return;
      const controller = new AbortController();
      const writeTimeout = 10000;
      const expiresAt = performance.now() + writeTimeout;
      const deadlineError = Error('Policy write deadline exceeded');
      const deadline = setTimeout(() => controller.abort(deadlineError),writeTimeout);
      try {
        const check = () => {
          controller.signal.throwIfAborted();
          if (performance.now() >= expiresAt) throw deadlineError;
          this.#checkObserved(incoming);
          checkTime();
        };
        if (await this.store.compareAndSwap(stored,incoming.envelope,{signal:controller.signal,check})) {
          // A durable commit advances the floor even if the acknowledged
          // revision has since expired or been superseded.
          this.#rememberPersisted(incoming);
          this.#checkObserved(incoming);
          checkTime();
          return;
        }
        controller.signal.throwIfAborted();
      } finally {
        clearTimeout(deadline);
      }
    }
    throw Error('Policy update contention');
  }
  async #load() {
    const value = await this.#read();
    if (value === null) throw Error('Authenticated policy unavailable; trusted checkpoint required');
    const checked = await this.#verify(value,false);
    this.#rememberPersisted(checked);
    this.#checkObserved(checked);
    if (checked.document.revision < this.#minimum) throw Error('Invalid policy scope or checkpoint');
    const initial = timestamp(this.clock());
    if (initial < checked.document.issuedAt || initial >= checked.document.expiresAt) throw Error('Policy is not current');
    if (!samePolicy(checked.envelope,await this.#read())) throw Error('Policy changed while checking');
    this.#checkObserved(checked);
    const now = timestamp(this.clock());
    if (now < checked.document.issuedAt || now >= checked.document.expiresAt) throw Error('Policy expired while checking');
    return checked;
  }
  /** Async compatibility assessments always reread authenticated storage, even through an old
   * handle. They are not signing capabilities; a final wallet boundary must still bind current
   * policy revision, context and immutable intent, as TradingSession does. */
  async current() {
    const checked = await this.#load();
    this.#checkObserved(checked);
    return Object.freeze({ revision:checked.document.revision, expiresAt:checked.document.expiresAt,
      registry:Object.freeze({
        allowNew:async(id:string,codeHash:string,scope:ProfileScope) => {
          const bound=Object.freeze({...scope});
          const fresh=await this.#load();
          this.#checkObserved(fresh);
          fresh.registry.allowNew(id,codeHash,bound);
        },
        allowRecovery:async(id:string,codeHash:string,scope:ProfileScope) => {
          const bound=Object.freeze({...scope});
          const fresh=await this.#load();
          this.#checkObserved(fresh);
          fresh.registry.allowRecovery(id,codeHash,bound);
        },
      }) });
  }
}

/** Dedicated bounded policy record, isolated from pending money-operation journals. */
export class IndexedDbPolicyStore implements PolicyStore {
  constructor(private readonly database: IDBDatabase) {
    if (!database.objectStoreNames.contains('gift-policy')) throw Error('Policy object store missing');
  }
  async read(): Promise<SignedPolicy | null> {
    return new Promise((resolve,reject) => {
      const tx = this.database.transaction('gift-policy','readonly'), request = tx.objectStore('gift-policy').get('current');
      let value: SignedPolicy | null = null;
      request.onsuccess = () => { value = request.result ?? null; };
      tx.oncomplete = () => resolve(value);
      tx.onabort = () => reject(Error('Policy read failed'));
      tx.onerror = () => { /* onabort reports failure */ };
    });
  }
  async compareAndSwap(expected: SignedPolicy | null, next: SignedPolicy, commit: PolicyCommit): Promise<boolean> {
    const candidate = copyEnvelope(next);
    commit.check();
    return new Promise((resolve,reject) => {
      const tx = this.database.transaction('gift-policy','readwrite',{durability:'strict'});
      if (tx.durability !== 'strict') { tx.abort(); reject(Error('Strict policy durability unavailable')); return; }
      const store = tx.objectStore('gift-policy'), request = store.get('current');
      let changed = false;
      let failure: unknown;
      const cancel = () => {
        try { tx.abort(); } catch { /* Commit already started or finished; wait for its result. */ }
      };
      const cleanup = () => commit.signal.removeEventListener('abort',cancel);
      request.onsuccess = () => {
        try {
          commit.check();
          if (samePolicy(request.result ?? null,expected)) { store.put(candidate,'current'); changed = true; }
        } catch (error) { failure = error; cancel(); }
      };
      tx.oncomplete = () => { cleanup(); resolve(changed); };
      tx.onabort = () => { cleanup(); reject(failure ?? commit.signal.reason ?? Error('Policy commit failed')); };
      tx.onerror = () => { /* onabort reports failure */ };
      commit.signal.addEventListener('abort',cancel,{once:true});
      if (commit.signal.aborted) cancel();
    });
  }
}
