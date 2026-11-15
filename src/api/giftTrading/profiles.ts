import { network, address } from './protocol.js';
import type { Chain } from './protocol.js';
export type ProfileScope = Readonly<{ chain: Chain; collection: string; environment: 'laboratory' | 'production' }>;
export type CompatibilityProfile = Readonly<{ id: string; codeHash: string; layout: string; chain: Chain;
  collections: readonly string[]; immutable: boolean; authenticatedAck: boolean;
  environment: 'laboratory' | 'production'; enabled: boolean; recoveryReviewed: boolean }>;
/** Configuration is wallet-owned, authenticated outside this module, never downloaded from an NFT. */
export class ProfileRegistry {
  #revision = -1;
  #profiles = new Map<string,CompatibilityProfile>();
  install(revision: number, profiles: readonly CompatibilityProfile[]): void {
    if (!Number.isSafeInteger(revision) || revision <= this.#revision || !Array.isArray(profiles) || profiles.length > 128) throw Error('Profile rollback or oversized policy');
    const next = new Map<string,CompatibilityProfile>();
    for (const p of profiles) {
      network(p.chain);
      if (!/^[a-z0-9-]{1,64}$/.test(p.id) || !/^[a-f0-9]{64}$/.test(p.codeHash) || !/^[a-z0-9-]{1,64}$/.test(p.layout)
        || !['laboratory','production'].includes(p.environment) || !Array.isArray(p.collections) || p.collections.length > 512
        || p.collections.some((c: unknown) => typeof c !== 'string' || !/^0:[a-f0-9]{64}$/.test(c)) || next.has(p.id)
        || [p.immutable,p.authenticatedAck,p.enabled,p.recoveryReviewed].some(v => typeof v !== 'boolean')) throw Error('Invalid profile');
      next.set(p.id,Object.freeze({ ...p, collections: Object.freeze([...p.collections]) }));
    }
    this.#profiles = next; this.#revision = revision;
  }
  get revision(): string { return String(this.#revision); }
  allowNew(id: string, codeHash: string, scope: ProfileScope): void {
    network(scope.chain); address(scope.collection);
    const p = this.#profiles.get(id);
    if (!p || !p.enabled || !p.immutable || !p.authenticatedAck || p.environment !== scope.environment || p.chain !== scope.chain || p.codeHash !== codeHash || !p.collections.includes(scope.collection)) throw Error('Unsupported or revoked NFT profile');
    // There is deliberately no approved production profile in this proposal.
    if (scope.environment === 'production') throw Error('Production gift trading is disabled');
  }
  /** Compatibility only; this does not prove NFT membership, past delivery or authorize payment. */
  allowRecovery(id: string, codeHash: string, scope: ProfileScope): void {
    network(scope.chain); address(scope.collection);
    const p = this.#profiles.get(id);
    // Revoking new trades must not silently revoke separately reviewed recovery.
    if (!p || !p.recoveryReviewed || p.codeHash !== codeHash || p.chain !== scope.chain
      || p.environment !== scope.environment || !p.collections.includes(scope.collection)) throw Error('Recovery needs independent review');
    if (scope.environment === 'production') throw Error('Production gift trading is disabled');
  }
}
