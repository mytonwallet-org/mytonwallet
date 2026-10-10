import type {
  AgentWalletDataAccountRowV31,
  AgentWalletDataQueryArgs,
  AgentWalletDataQueryResult,
  AgentWalletResolvedScopeV1,
} from './protocol/types';
import type { AgentV2HostAccount } from './types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';
import type { AgentV2WalletSessionSnapshot } from './walletSession';

import {
  isBoundedText,
  makeCoverage,
  maskIdentifier,
  normalizeSearch,
  requestedAccountCount,
  requireAccountRef,
  resolvedBase,
  safeWalletQueryAccountLabel,
  safeWalletQueryIdentifierDisplay,
  uniqueLimitations,
} from './walletQueryOutput';
import { buildAccountPortfolioTotal, getPositionSourceStatus, positionStateLimitations } from './walletQueryPositions';
import { canonicalWalletQueryRowId } from './walletQueryRowId';

export function buildAccounts(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'account.inventory' }>,
): Extract<AgentWalletDataQueryResult, { operation: 'account.inventory' }> {
  const requestedChains = args.chains.length ? new Set(args.chains) : undefined;
  const rows = accounts.flatMap((account) => {
    const chains = [...new Set(account.chains.filter((chain) => !requestedChains || requestedChains.has(chain)))];
    if (!chains.length && requestedChains) return [];
    const publicAddresses = args.includePublicAddressReason && account.state === 'active'
      ? chains.flatMap((chain) => {
        const address = account.addresses[chain];
        return address && isBoundedText(address, 256) ? [{
          chain,
          address,
          disclosureReason: args.includePublicAddressReason!,
        }] : [];
      })
      : undefined;
    const portfolio = args.includePortfolioTotals
      ? buildAccountPortfolioTotal(dependencies.session, snapshot, account, args.chains)
      : undefined;
    return [{
      rowId: canonicalWalletQueryRowId('account', requireAccountRef(snapshot, account)),
      kind: 'account' as const,
      accountRef: requireAccountRef(snapshot, account),
      accountLabel: safeWalletQueryAccountLabel(account),
      accountType: account.accountType,
      isCurrent: account.accountId === snapshot.host?.activeAccountId,
      state: account.state,
      isViewOnly: account.isViewOnly,
      chains,
      ...accountPortfolioFields(portfolio),
      ...(publicAddresses?.length ? { publicAddresses } : {}),
    }];
  }).slice(0, 100);
  const omitted = 0;
  const unavailableCount = rows.filter(({ portfolioTotalStatus }) => (
    portfolioTotalStatus === 'unavailable'
  )).length;
  const positionLimitations = positionStateLimitations(accounts, args.chains);
  const unpricedCount = rows.reduce((sum, row) => sum + (row.portfolioTotal?.unpricedCount ?? 0), 0);
  const limitations = args.includePortfolioTotals ? uniqueLimitations([
    ...(unavailableCount ? ['source_unavailable' as const] : []),
    ...positionLimitations,
    ...(unpricedCount ? ['unpriced_positions' as const] : []),
  ]) : [];
  const coverage = makeCoverage({
    domain: 'accounts',
    sourceStatus: args.includePortfolioTotals ? getPositionSourceStatus(accounts, args.chains) : undefined,
    accountsRequested: requestedAccountCount(dependencies, accounts),
    accountsIncluded: args.includePortfolioTotals ? accounts.length - unavailableCount : accounts.length,
    rowsOmitted: omitted,
    limitations,
    rowCount: rows.length,
  });
  return {
    ...resolvedBase(dependencies, resolvedScope, coverage),
    operation: 'account.inventory',
    accounts: rows,
  };
}

function accountPortfolioFields(
  portfolio: ReturnType<typeof buildAccountPortfolioTotal> | undefined,
): AgentWalletDataAccountRowV31 {
  if (!portfolio) return {};
  return portfolio.status !== 'unavailable' && portfolio.total
    ? { portfolioTotalStatus: portfolio.status, portfolioTotal: portfolio.total }
    : { portfolioTotalStatus: 'unavailable' };
}

export function buildContacts(
  dependencies: WalletQueryMaterializationDependencies,
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  resolvedScope: AgentWalletResolvedScopeV1,
  args: Extract<AgentWalletDataQueryArgs, { operation: 'contacts.list' }>,
): Extract<AgentWalletDataQueryResult, { operation: 'contacts.list' }> {
  const isSendRecipientContext = args.purpose === 'send_recipient_resolution';
  const { items, missingBindings, sourceAccounts } = collectWalletContacts(
    dependencies.session, snapshot, accounts, args,
  );
  const rows = items.map(({ row }) => row);
  const contacts = rows.slice(0, args.pageSize);
  const omitted = Math.max(0, rows.length - contacts.length) + missingBindings;
  const missingSources = sourceAccounts.filter(({ domainStates }) => (
    domainStates?.contacts?.state === 'notLoaded' || domainStates?.contacts?.state === 'unavailable'
  )).length;
  const limitations = uniqueLimitations([
    ...(rows.length > contacts.length ? ['row_limit' as const] : []),
    ...(missingBindings || missingSources ? ['source_partial' as const] : []),
  ]);
  return {
    ...resolvedBase(dependencies, resolvedScope, makeCoverage({
      domain: 'contacts',
      accountsRequested: isSendRecipientContext ? sourceAccounts.length : requestedAccountCount(dependencies, accounts),
      accountsIncluded: Math.max(0, sourceAccounts.length - missingSources),
      rowsOmitted: omitted,
      limitations,
      rowCount: contacts.length,
    })),
    operation: 'contacts.list',
    contacts,
  };
}

export function collectWalletContacts(
  session: WalletQueryMaterializationDependencies['session'],
  snapshot: AgentV2WalletSessionSnapshot,
  accounts: AgentV2HostAccount[],
  args: Pick<
    Extract<AgentWalletDataQueryArgs, { operation: 'contacts.list' }>,
    'purpose' | 'chains' | 'query' | 'ownWalletChains'
  >,
  includeAll = false,
) {
  const isSendRecipientContext = args.purpose === 'send_recipient_resolution';
  const sourceAccounts = isSendRecipientContext
    ? (snapshot.host?.accounts ?? []).filter(({ state }) => state !== 'deleted')
    : accounts;
  const query = args.query ? normalizeSearch(args.query) : undefined;
  let missingBindings = 0;
  const savedSources = sourceAccounts.flatMap((account) => (account.savedAddresses ?? []).map((contact) => ({
    contact,
    accountRef: requireAccountRef(snapshot, account) as string | undefined,
    source: 'saved' as 'saved' | 'profile',
    rowKey: `${requireAccountRef(snapshot, account)}\0${contact.id}`,
    refs: session.resolveSavedAddressRefs(account.accountId, contact.id),
  })));
  if (isSendRecipientContext) {
    savedSources.push(...(snapshot.host?.savedAddresses ?? []).map((contact) => ({
      contact,
      accountRef: undefined,
      source: 'profile' as const,
      rowKey: `profile\0${contact.id}`,
      refs: session.resolveProfileSavedAddressRefs(contact.id),
    })));
  }
  const seenContacts = new Map<string, string>();
  const savedAddressRows = savedSources.flatMap(({ contact, refs, rowKey, accountRef, source }) => {
    if (args.chains.length && !args.chains.includes(contact.chain)) return [];
    if (query && !normalizeSearch(`${contact.name} ${contact.address}`).includes(query)) return [];
    if (!refs) {
      missingBindings += 1;
      return [];
    }
    const identity = `${normalizeSearch(contact.name)}\0${contact.chain}\0${contact.address}`;
    if (!includeAll && isSendRecipientContext && seenContacts.has(identity)) return [];
    const identityRef = seenContacts.get(identity) ?? refs.contactRef;
    seenContacts.set(identity, identityRef);
    return [{ accountRef, source, identityRef, row: {
      rowId: canonicalWalletQueryRowId('contact', rowKey),
      kind: 'contact' as const,
      contactRef: refs.contactRef,
      addressRef: refs.addressRef,
      name: safeWalletQueryIdentifierDisplay(contact.name, contact.address, 160),
      chain: contact.chain,
      addressDisplay: maskIdentifier(contact.address),
    } }];
  });
  const scopedAccountIds = new Set(accounts.map(({ accountId }) => accountId));
  const ownWalletRows = (snapshot.host?.accounts ?? []).flatMap((account) => {
    if ((!isSendRecipientContext && scopedAccountIds.has(account.accountId)) || account.state === 'deleted') return [];
    const name = safeWalletQueryAccountLabel(account);
    // Own wallets are listed on the networks the read names alone, such as a transfer's, while `chains` selects
    // the saved addresses
    return [...new Set(args.ownWalletChains)].flatMap((chain) => {
      const address = account.addresses[chain];
      if (!address || (query && !normalizeSearch(`${name} ${address}`).includes(query))) return [];
      const refs = session.resolveWalletAddressRefs(account.accountId, chain);
      if (!refs) {
        missingBindings += 1;
        return [];
      }
      return [{ accountRef: requireAccountRef(snapshot, account), source: 'own_wallet' as const,
        identityRef: refs.contactRef, row: {
          rowId: canonicalWalletQueryRowId(
            'contact', `${requireAccountRef(snapshot, account)}\0own-wallet\0${chain}`,
          ),
          kind: 'contact' as const,
          contactRef: refs.contactRef,
          addressRef: refs.addressRef,
          name,
          chain,
          addressDisplay: maskIdentifier(address),
        } }];
    });
  });
  return { items: [...savedAddressRows, ...ownWalletRows], missingBindings, sourceAccounts };
}
