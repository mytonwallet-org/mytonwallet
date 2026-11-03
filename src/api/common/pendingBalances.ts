import type { ApiBalanceBySlug, ApiChain, ApiNetwork, ApiUpdateBalances, OnApiUpdate } from '../types';

import { parseAccountId } from '../../util/account';
import { getChainConfig } from '../../util/chain';
import { getNativeToken } from '../../util/tokens';
import { MINUTE } from '../constants';

const PENDING_BALANCE_TTL = 15 * MINUTE;

type PendingDebit = {
  amount: bigint;
  timeout: ReturnType<typeof setTimeout>;
};

type ObservedBalance = {
  value: bigint;
  debits: Set<PendingDebit>;
};

const balancesByAccount = new Map<string, Map<ApiChain, Map<string, ObservedBalance>>>();

/** Records network observations before applying the pending transfers shown to the app. */
export function applyPendingBalances(update: ApiUpdateBalances): ApiUpdateBalances {
  const { accountId, chain, balances } = update;
  if (!getChainConfig(chain).shouldUsePendingBalances) return update;

  let accountBalances = balancesByAccount.get(accountId);
  if (!accountBalances) {
    accountBalances = new Map();
    balancesByAccount.set(accountId, accountBalances);
  }
  let chainBalances = accountBalances.get(chain);
  if (!chainBalances) {
    chainBalances = new Map();
    accountBalances.set(chain, chainBalances);
  }

  for (const [slug, balance] of chainBalances) {
    if (!(slug in balances)) {
      clearDebits(balance);
      chainBalances.delete(slug);
    }
  }

  const displayedBalances: ApiBalanceBySlug = {};
  for (const [slug, value] of Object.entries(balances)) {
    let balance = chainBalances.get(slug);
    if (!balance) {
      balance = { value, debits: new Set() };
      chainBalances.set(slug, balance);
    } else if (balance.value !== value) {
      clearDebits(balance);
      balance.value = value;
    }
    displayedBalances[slug] = getDisplayedBalance(balance);
  }

  return { ...update, balances: displayedBalances };
}

export function capturePendingTransferBalances(accountId: string, chain: ApiChain, slug: string): ApiBalanceBySlug {
  const balances: ApiBalanceBySlug = {};
  if (!getChainConfig(chain).shouldUsePendingBalances) return balances;
  const chainBalances = balancesByAccount.get(accountId)?.get(chain);

  for (const tokenSlug of [slug, getNativeToken(chain).slug]) {
    const balance = chainBalances?.get(tokenSlug);
    if (balance) balances[tokenSlug] = balance.value;
  }

  return balances;
}

export function registerPendingTransfer(
  accountId: string,
  chain: ApiChain,
  transaction: { slug: string; amount: bigint; fee: bigint },
  balancesBeforeTransfer: ApiBalanceBySlug,
  onUpdate: OnApiUpdate,
) {
  if (!getChainConfig(chain).shouldUsePendingBalances) return;
  const chainBalances = balancesByAccount.get(accountId)?.get(chain);
  if (!chainBalances) return;

  const { slug, amount, fee } = transaction;
  const nativeSlug = getNativeToken(chain).slug;
  const amounts: ApiBalanceBySlug = { [slug]: amount };
  amounts[nativeSlug] = (amounts[nativeSlug] ?? 0n) + fee;
  let hasDebits = false;

  for (const [debitSlug, debitAmount] of Object.entries(amounts)) {
    const balance = chainBalances.get(debitSlug);
    if (!balance || balance.value !== balancesBeforeTransfer[debitSlug] || debitAmount === 0n) continue;

    const debit: PendingDebit = {
      amount: debitAmount,
      timeout: setTimeout(() => {
        balance.debits.delete(debit);
        onUpdate({
          type: 'updateBalances',
          accountId,
          chain,
          balances: getDisplayedBalances(chainBalances),
        });
      }, PENDING_BALANCE_TTL),
    };
    balance.debits.add(debit);
    hasDebits = true;
  }

  if (hasDebits) {
    onUpdate({ type: 'updateBalances', accountId, chain, balances: getDisplayedBalances(chainBalances) });
  }
}

export function clearPendingBalances(accountId: string) {
  const accountBalances = balancesByAccount.get(accountId);
  if (!accountBalances) return;

  for (const chainBalances of accountBalances.values()) {
    for (const balance of chainBalances.values()) {
      clearDebits(balance);
    }
  }
  balancesByAccount.delete(accountId);
}

export function clearNetworkPendingBalances(network: ApiNetwork) {
  for (const accountId of balancesByAccount.keys()) {
    if (parseAccountId(accountId).network === network) clearPendingBalances(accountId);
  }
}

export function clearAllPendingBalances() {
  for (const accountId of balancesByAccount.keys()) {
    clearPendingBalances(accountId);
  }
}

function getDisplayedBalances(chainBalances: Map<string, ObservedBalance>): ApiBalanceBySlug {
  return Object.fromEntries(Array.from(chainBalances, ([slug, balance]) => [slug, getDisplayedBalance(balance)]));
}

function getDisplayedBalance(balance: ObservedBalance) {
  let value = balance.value;
  for (const debit of balance.debits) {
    value -= debit.amount;
  }
  return value > 0n ? value : 0n;
}

function clearDebits(balance: ObservedBalance) {
  for (const debit of balance.debits) {
    clearTimeout(debit.timeout);
  }
  balance.debits.clear();
}
