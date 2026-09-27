import type { ApiBaseCurrency, ApiCurrencyRates, ApiDappTransfer, ApiTokenWithPrice } from '../../api/types';
import type { GlobalState } from '../types';

import { STON_PTON_SLUG, TONCOIN, UNKNOWN_TOKEN } from '../../config';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { getChainConfig } from '../../util/chain';
import { toBig } from '../../util/decimals';
import memoize from '../../util/memoize';
import { isNftTransferPayload, isTokenTransferPayload } from '../../util/ton/transfer';
import { selectCurrentAccountState } from './accounts';

// Cheap operations are dominated by the network fee, so showing their total would only mislead
const MIN_TOTAL_AMOUNT_USD = 0.5;

const selectCurrentDappTransferTotalsMemoized = memoize((
  transactions: ApiDappTransfer[] | undefined,
) => {
  const amountsBySlug: Record<string, bigint> = {};
  const addSlugAmount = (tokenSlug: string, amount: bigint) => {
    amountsBySlug[tokenSlug] = (amountsBySlug[tokenSlug] ?? 0n) + amount;
  };

  let isScam = false;
  let isDangerous = false;
  let nftCount = 0;

  for (const transaction of transactions ?? []) {
    if (transaction.isScam) isScam = true;
    if (transaction.isDangerous) isDangerous = true;

    addSlugAmount(getChainConfig(transaction.chain).nativeToken.slug, transaction.amount + transaction.networkFee);

    if (isTokenTransferPayload(transaction.payload)) {
      addSlugAmount(transaction.payload.slug, transaction.payload.amount);
    } else if (isNftTransferPayload(transaction.payload)) {
      nftCount++;
    }
  }

  return {
    amountsBySlug,
    isScam,
    isDangerous,
    nftCount,
  };
});

const selectDappTransferInsufficientTokensMemoized = memoize((
  amountsBySlug: Record<string, bigint>,
  balances: Record<string, bigint> | undefined,
  tokensBySlug: Record<string, ApiTokenWithPrice> | undefined,
): string | undefined => {
  if (!balances || !tokensBySlug) {
    return undefined;
  }

  const insufficientTokens: string[] = [];

  for (const [slug, requiredAmount] of Object.entries(amountsBySlug)) {
    const token = tokensBySlug[slug] ?? UNKNOWN_TOKEN;

    // pTON is the STON.fi wrapper that lets its routers swap Toncoin as if it were a jetton. The wallet never holds
    // pTON: a swap attaches Toncoin to the message, and the router's pTON wallet wraps it. So the pTON amount must be
    // covered by the Toncoin balance, and a shortage is reported as a lack of Toncoin.
    const balanceSlug = slug === STON_PTON_SLUG ? TONCOIN.slug : slug;
    const availableBalance = balances[balanceSlug] ?? 0n;

    if (availableBalance < requiredAmount) {
      const symbol = slug === STON_PTON_SLUG ? TONCOIN.symbol : token.symbol;
      insufficientTokens.push(symbol);
    }
  }

  return insufficientTokens.length > 0 ? insufficientTokens.join(', ') : undefined;
});

export function selectCurrentDappTransferTotals(global: GlobalState) {
  const { transactions } = global.currentDappTransfer;
  return selectCurrentDappTransferTotalsMemoized(transactions);
}

/**
 * The value of everything leaving the wallet, including the network fees, in the base currency.
 *
 * Tokens with an unknown price are skipped, so NFT-only requests end up with no value at all.
 * Returns `undefined` when the value is too small to tell the user anything useful.
 */
export const selectDappTransferTotalInBaseCurrency = memoize((
  amountsBySlug: Record<string, bigint>,
  tokensBySlug: Record<string, ApiTokenWithPrice>,
  baseCurrency: ApiBaseCurrency,
  currencyRates: ApiCurrencyRates,
): string | undefined => {
  let totalUsd = 0;

  for (const [slug, amount] of Object.entries(amountsBySlug)) {
    // A STON.fi swap from Toncoin sends the Toncoin itself as the message amount, which is already in the Toncoin
    // total. The payload repeats the same value as a pTON transfer, so pricing it would count the swap twice.
    if (slug === STON_PTON_SLUG) continue;

    const token = tokensBySlug[slug];
    if (!token?.priceUsd) continue;

    totalUsd += toBig(amount, token.decimals).toNumber() * token.priceUsd;
  }

  if (totalUsd <= MIN_TOTAL_AMOUNT_USD) {
    return undefined;
  }

  return calculateTokenPrice(totalUsd, baseCurrency, currencyRates).toString();
});

export function selectCurrentDappTransferTotalInBaseCurrency(global: GlobalState) {
  const { amountsBySlug } = selectCurrentDappTransferTotals(global);

  return selectDappTransferTotalInBaseCurrency(
    amountsBySlug,
    global.tokenInfo.bySlug,
    global.settings.baseCurrency,
    global.currencyRates,
  );
}

export function selectDappTransferInsufficientTokens(global: GlobalState): string | undefined {
  const accountState = selectCurrentAccountState(global);
  const balances = accountState?.balances?.bySlug;
  const tokensBySlug = global.tokenInfo.bySlug;
  const { amountsBySlug } = selectCurrentDappTransferTotals(global);

  return selectDappTransferInsufficientTokensMemoized(amountsBySlug, balances, tokensBySlug);
}
