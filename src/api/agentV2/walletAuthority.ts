import type { AgentV2HostContextSnapshot } from './types';

import { sha256 } from '../common/utils';

interface AuthorityBinding {
  readonly accountDigest: string;
  readonly profileDigest: string;
  readonly revision: number;
  readonly sessionId: string;
}

interface WalletAuthoritySnapshot {
  readonly authorityFingerprint: string;
  readonly queryFingerprint: string;
  bind(sessionId: string, revision: number): Promise<AuthorityBinding>;
}

export function createWalletAuthoritySnapshot(
  host?: AgentV2HostContextSnapshot,
  previous?: WalletAuthoritySnapshot,
): WalletAuthoritySnapshot {
  const projection = queryAuthorityProjection(host);
  const authorityFingerprint = buildAuthorityFingerprint(host);
  const queryFingerprint = JSON.stringify(projection);
  if (previous?.authorityFingerprint === authorityFingerprint && previous.queryFingerprint === queryFingerprint) {
    return previous;
  }
  const accountInput = JSON.stringify({
    activeAccountId: host?.activeAccountId,
    activeNetwork: host?.activeNetwork,
    accounts: projection.accounts,
  });
  const profileInput = JSON.stringify({
    accounts: projection.profileAccounts,
    savedAddresses: projection.savedAddresses,
  });
  let cached: { sessionId: string; revision: number; promise: Promise<AuthorityBinding> } | undefined;
  return Object.freeze({
    authorityFingerprint,
    queryFingerprint,
    bind(sessionId: string, revision: number) {
      if (cached?.sessionId === sessionId && cached.revision === revision) return cached.promise;
      const promise = Promise.all([
        sha256(new TextEncoder().encode(accountInput)),
        sha256(new TextEncoder().encode(profileInput)),
      ]).then(([accountDigest, profileDigest]) => Object.freeze({
        accountDigest: toBase64Url(new Uint8Array(accountDigest)),
        profileDigest: toBase64Url(new Uint8Array(profileDigest)),
        revision,
        sessionId,
      })).catch((error: unknown) => {
        if (cached?.promise === promise) cached = undefined;
        throw error;
      });
      cached = { sessionId, revision, promise };
      return promise;
    },
  });
}

// Selecting another available wallet does not revoke access to the existing wallet inventory.
export function isWalletSelectionChange(
  previous: AgentV2HostContextSnapshot | undefined,
  next: AgentV2HostContextSnapshot | undefined,
) {
  if (!previous || !next || !previous.activeAccountId || !next.activeAccountId
    || !next.accounts.some((account) => account.accountId === next.activeAccountId && account.state === 'active')) {
    return false;
  }
  return previous.activeAccountId !== next.activeAccountId
    && buildAuthorityFingerprint({
      ...previous,
      activeAccountId: next.activeAccountId,
      activeNetwork: next.activeNetwork,
    }) === buildAuthorityFingerprint(next);
}

function queryAuthorityProjection(snapshot?: AgentV2HostContextSnapshot) {
  const accounts = (snapshot?.accounts ?? []).map((account) => ({
    accountId: account.accountId,
    accountType: account.accountType,
    chains: [...account.chains].sort(),
    isViewOnly: account.isViewOnly,
    state: account.state,
  })).sort((left, right) => left.accountId.localeCompare(right.accountId));
  const profileAccounts = (snapshot?.accounts ?? []).map((account) => ({
    accountId: account.accountId,
    addresses: Object.entries(account.addresses)
      .filter((entry): entry is [string, string] => Boolean(entry[1]))
      .sort(([left], [right]) => left.localeCompare(right)),
    label: account.label ?? '',
    portfolioWalletKeys: [...(account.portfolioWalletKeys ?? [])].sort(),
    savedAddresses: [...(account.savedAddresses ?? [])].map((entry) => ({
      address: entry.address,
      chain: entry.chain,
      id: entry.id,
      name: entry.name,
    })).sort((left, right) => left.id.localeCompare(right.id)),
  })).sort((left, right) => left.accountId.localeCompare(right.accountId));
  const savedAddresses = [...(snapshot?.savedAddresses ?? [])].map((entry) => ({
    address: entry.address,
    chain: entry.chain,
    id: entry.id,
    name: entry.name,
  })).sort((left, right) => left.id.localeCompare(right.id));
  return { accounts, profileAccounts, savedAddresses };
}

function buildAuthorityFingerprint(snapshot?: AgentV2HostContextSnapshot): string {
  if (!snapshot) return 'none';
  return JSON.stringify({
    activeAccountId: snapshot.activeAccountId,
    activeNetwork: snapshot.activeNetwork,
    accounts: snapshot.accounts.map((account) => ({
      accountId: account.accountId,
      accountType: account.accountType,
      addresses: Object.entries(account.addresses)
        .filter((entry): entry is [string, string] => Boolean(entry[1]))
        .sort(([left], [right]) => left.localeCompare(right)),
      state: account.state,
      isViewOnly: account.isViewOnly,
      chains: [...account.chains].sort(),
    })).sort((left, right) => left.accountId.localeCompare(right.accountId)),
    isTestnet: snapshot.isTestnet,
  });
}

function toBase64Url(bytes: Uint8Array) {
  let binary = '';
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/u, '');
}
