import { AuthenticatedProfilePolicy } from './profile-policy.js';
import type { PolicyCommit, PolicyStore, SignedPolicy } from './profile-policy.js';
import { timestamp } from './protocol.js';

/** This name must be fixed by trusted app configuration and shared by every policy
 * writer/confirmation for one store. Web Locks are origin-scoped, not a chain authority. */
export class LockedPolicyStore implements PolicyStore {
  readonly name: string;
  constructor(private readonly store: PolicyStore, readonly locks: LockManager, name: string) {
    if (!locks || typeof locks.request !== 'function' || !/^[a-z0-9-]{1,96}$/.test(name)) throw Error('Policy locking unavailable');
    this.name = 'gift-policy-' + name;
  }
  read(): Promise<SignedPolicy | null> { return this.store.read(); }
  compareAndSwap(expected: SignedPolicy | null, next: SignedPolicy, commit: PolicyCommit): Promise<boolean> {
    return this.locks.request(this.name, {mode:'exclusive',signal:commit.signal}, () => {
      commit.check();
      return this.store.compareAndSwap(expected,next,commit);
    });
  }
}

/** Local confirmation coordination, NOT a signed authorization capability.
 * The caller must still bind the immutable intent, profile eligibility and account.
 * A pending revocation waits for this bounded lease; an already committed one is seen.
 * No wallet lock is acquired and no keys or money-operation transport are accessed. */
export class ConfirmationPolicyBoundary {
  constructor(private readonly store: LockedPolicyStore, private readonly policy: AuthenticatedProfilePolicy,
    private readonly clock: () => number, private readonly monotonic: () => number = () => performance.now()) {}
  async run(revision: string, signal: AbortSignal, work: (guard: () => void) => Promise<void>): Promise<void> {
    if (!/^(0|[1-9][0-9]{0,15})$/.test(revision) || !Number.isSafeInteger(Number(revision))) throw Error('Invalid bound policy revision');
    const started = this.monotonic(), wallStarted = timestamp(this.clock());
    if (!Number.isFinite(started) || started < 0) throw Error('Invalid monotonic clock');
    const controller = new AbortController(), abort = () => controller.abort(signal.reason);
    if (signal.aborted) abort(); else signal.addEventListener('abort',abort,{once:true});
    const timer = setTimeout(()=>controller.abort(Error('Policy boundary deadline')),15000);
    try {
      await this.store.locks.request(this.store.name,{mode:'shared',signal:controller.signal},async()=>{
        let active = true;
        let onAbort: (()=>void) | undefined;
        const cancelled = new Promise<never>((_,reject)=>{
          onAbort=()=>reject(controller.signal.reason ?? Error('Cancelled policy lease'));
          controller.signal.addEventListener('abort',onAbort,{once:true});
          if(controller.signal.aborted)onAbort();
        });
        try {
          const operation = async () => {
          controller.signal.throwIfAborted();
          const current = await this.policy.current();
          if (String(current.revision) !== revision) throw Error('Reviewed policy was superseded');
          const guard = () => {
            controller.signal.throwIfAborted();
            const elapsed = this.monotonic() - started, now = timestamp(this.clock());
            if (!active || !Number.isFinite(elapsed) || elapsed < 0 || elapsed >= 15000
              || now < wallStarted || now >= current.expiresAt) throw Error('Policy lease expired');
          };
          guard();
          // Racing the abort releases the lock even if an uncooperative callback never
          // settles. Its retained guard becomes unusable before any later continuation.
          await work(guard);guard();
          };
          await Promise.race([operation(),cancelled]);
        } finally { active = false;if(onAbort)controller.signal.removeEventListener('abort',onAbort); }
      });
    } finally { clearTimeout(timer);signal.removeEventListener('abort',abort); }
  }
}
