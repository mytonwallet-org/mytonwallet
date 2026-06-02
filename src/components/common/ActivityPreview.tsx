import React, { memo } from '../../lib/teact/teact';

import type {
  ApiActivity,
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiNft,
  ApiStakingState,
  ApiSwapAsset,
  ApiToken,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, AppTheme, SavedAddress } from '../../global/types';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';

import Activity from '../main/sections/Content/Activity';
import FeeLine from '../ui/FeeLine';
import IconWithTooltip from '../ui/IconWithTooltip';

import styles from './ActivityPreview.module.scss';

type OwnProps = {
  activities?: ApiActivity[];
  realFee?: bigint;
  feeToken?: Pick<ApiToken, 'slug' | 'symbol' | 'decimals'>;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  appTheme: AppTheme;
  nftsByAddress?: Record<string, ApiNft>;
  currentAccountId: string;
  stakingStateBySlug: Record<string, ApiStakingState>;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  shouldHideStakingAnnualYield?: boolean;
  className?: string;
};

function ActivityPreview({
  activities,
  realFee,
  feeToken,
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
  shouldHideStakingAnnualYield,
  className,
}: OwnProps) {
  const lang = useLang();

  if (!activities?.length) {
    return undefined;
  }

  const visibleActivities = activities.filter((activity) => !activity.shouldHide);
  if (!visibleActivities.length) {
    return undefined;
  }

  return (
    <div className={className}>
      <p className={styles.label}>
        {lang('Preview')}
        {' '}
        <IconWithTooltip message={renderText(lang('$preview_not_guaranteed'))} type="warning" size="small" />
      </p>
      <div className={styles.activityList}>
        {visibleActivities.map((activity, index) => (
          <Activity
            key={activity.id}
            activity={activity}
            isFuture
            isLast={index === visibleActivities.length - 1}
            tokensBySlug={tokensBySlug}
            swapTokensBySlug={swapTokensBySlug}
            appTheme={appTheme}
            nftsByAddress={nftsByAddress}
            currentAccountId={currentAccountId}
            stakingStateBySlug={stakingStateBySlug}
            savedAddresses={savedAddresses}
            accounts={accounts}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            shouldHideStakingAnnualYield={shouldHideStakingAnnualYield}
          />
        ))}
      </div>
      {feeToken && realFee !== undefined && realFee !== 0n && (
        <FeeLine
          terms={{ native: realFee }}
          token={feeToken}
          precision="approximate"
          className={buildClassName(styles.fee)}
        />
      )}
    </div>
  );
}

export default memo(ActivityPreview);
