import React from '../../../../lib/teact/teact';

import type {
  ApiActivity,
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiNft,
  ApiStakingState,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../../../api/types';
import type { Account, AppTheme, SavedAddress } from '../../../../global/types';

import Swap, { getSwapHeight } from './Swap';
import Transaction, { getTransactionHeight } from './Transaction';

interface OwnProps {
  activity: ApiActivity;
  isLast?: boolean;
  isActive?: boolean;
  isSensitiveDataHidden?: boolean;
  isFuture?: boolean;
  withChainIcon?: boolean;
  className?: string;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug: Record<string, ApiSwapAsset> | undefined;
  appTheme: AppTheme;
  nftsByAddress: Record<string, ApiNft> | undefined;
  currentAccountId: string;
  stakingStateBySlug: Record<string, ApiStakingState>;
  savedAddresses: SavedAddress[] | undefined;
  accounts: Record<string, Account> | undefined;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  onClick?: (id: string) => void;
}

export default function Activity({
  activity,
  isLast,
  isActive,
  isSensitiveDataHidden,
  isFuture,
  withChainIcon,
  className,
  tokensBySlug,
  swapTokensBySlug,
  appTheme,
  nftsByAddress,
  currentAccountId,
  stakingStateBySlug,
  savedAddresses,
  accounts,
  baseCurrency,
  currencyRates,
  onClick,
}: OwnProps) {
  if (activity.kind === 'swap') {
    return (
      <Swap
        activity={activity}
        tokensBySlug={tokensBySlug}
        swapTokensBySlug={swapTokensBySlug}
        isLast={isLast}
        isActive={isActive}
        className={className}
        appTheme={appTheme}
        accountChains={accounts?.[currentAccountId]?.byChain}
        isSensitiveDataHidden={isSensitiveDataHidden}
        isFuture={isFuture}
        onClick={onClick}
      />
    );
  } else {
    const doesNftExist = Boolean(activity.nft && nftsByAddress?.[activity.nft.address]);
    const { annualYield, yieldType } = stakingStateBySlug[activity.slug] ?? {};

    return (
      <Transaction
        currentAccountId={currentAccountId}
        transaction={activity}
        tokensBySlug={tokensBySlug}
        isActive={isActive}
        className={className}
        annualYield={annualYield}
        yieldType={yieldType}
        isLast={isLast}
        savedAddresses={savedAddresses}
        withChainIcon={withChainIcon}
        appTheme={appTheme}
        doesNftExist={doesNftExist}
        isSensitiveDataHidden={isSensitiveDataHidden}
        isFuture={isFuture}
        accounts={accounts}
        baseCurrency={baseCurrency}
        currencyRates={currencyRates}
        onClick={onClick}
      />
    );
  }
}

export function getActivityHeight(activity: ApiActivity, isFuture?: boolean) {
  return activity.kind === 'swap' ? getSwapHeight() : getTransactionHeight(activity, isFuture);
}
