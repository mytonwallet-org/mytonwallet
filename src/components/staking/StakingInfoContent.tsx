import React, {
  memo, type TeactNode, useEffect, useMemo,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingHistory, ApiStakingState, ApiTokenWithPrice,
} from '../../api/types';
import type { Theme, UserToken } from '../../global/types';

import {
  ANIMATED_STICKER_TINY_ICON_PX,
  ETHENA_ELIGIBILITY_CHECK_URL,
  SHORT_FRACTION_DIGITS,
  TONCOIN,
} from '../../config';
import {
  selectAccountStakingHistory,
  selectAccountStakingState,
  selectAccountStakingStates,
  selectAccountStakingTotalProfit,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { formatRelativeHumanDateTime } from '../../util/dateFormat';
import { toBig, toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { openUrl } from '../../util/openUrl';
import { getIsNewStakeAllowed, getStakingStateStatus, getUnstakeTime } from '../../util/staking';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useAppTheme from '../../hooks/useAppTheme';
import useForceUpdate from '../../hooks/useForceUpdate';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useWindowSize from '../../hooks/useWindowSize';
import { useTokenDropdown } from './hooks/useTokenDropdown';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import RichNumberField from '../ui/RichNumberField';
import Spinner from '../ui/Spinner';
import TokenDropdown from '../ui/TokenDropdown';
import Transition from '../ui/Transition';
import StakingProfitItem from './StakingProfitItem';

import styles from './Staking.module.scss';

interface OwnProps {
  isActive?: boolean;
  onClose?: NoneToVoidFunction;
}

interface StateProps {
  isViewMode: boolean;
  states?: ApiStakingState[];
  stakingState?: ApiStakingState;
  totalProfit: bigint;
  stakingHistory?: ApiStakingHistory;
  tokens?: UserToken[];
  tokenBySlug?: Record<string, ApiTokenWithPrice>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  theme: Theme;
  shouldUseNominators?: boolean;
  isSensitiveDataHidden?: true;
}

const UPDATE_UNSTAKE_DATE_INTERVAL_MS = 30000; // 30 sec
const HISTORY_SCROLL_APPEARANCE_HEIGHT_PX = 640;
const FRACTION_DIGITS = 2;

function StakingInfoContent({
  states,
  stakingState,
  isActive,
  totalProfit,
  stakingHistory,
  tokens,
  tokenBySlug,
  baseCurrency,
  currencyRates,
  theme,
  shouldUseNominators,
  isViewMode,
  isSensitiveDataHidden,
  onClose,
}: OwnProps & StateProps) {
  const {
    startStaking,
    startUnstaking,
    startStakingClaim,
    fetchStakingHistory,
    changeCurrentStaking,
  } = getActions();

  const {
    id: stakingId,
    tokenSlug,
    balance: amount,
    annualYield = 0,
    unstakeRequestAmount,
    type: stakingType,
  } = stakingState ?? {};
  const isEthenaBoostAvailable = stakingState?.type === 'ethena' && stakingState.isBoostAvailable;

  const unstakeTime = getUnstakeTime(stakingState);
  const canBeClaimed = stakingState ? getStakingStateStatus(stakingState) === 'readyToClaim' : undefined;

  const token = useMemo(() => {
    return tokenSlug ? tokens?.find(({ slug }) => tokenSlug === slug) : undefined;
  }, [tokenSlug, tokens]);

  const { decimals, symbol } = token ?? {};

  const lang = useLang();
  const isLoading = amount === undefined;
  const hasHistory = Boolean(stakingHistory?.length);
  const {
    shouldRender: shouldRenderSpinner,
    ref: spinnerRef,
  } = useShowTransition({
    isOpen: isLoading && isActive,
    withShouldRender: true,
  });
  const tonToken = useMemo(() => tokens?.find(({ slug }) => slug === TONCOIN.slug), [tokens])!;
  const forceUpdate = useForceUpdate();
  const { height } = useWindowSize();
  const appTheme = useAppTheme(theme);
  const {
    shouldRender: shouldRenderTotalAmount,
    ref: totalAmountRef,
  } = useShowTransition({
    isOpen: !isSensitiveDataHidden,
    withShouldRender: true,
  });

  const unclaimedRewards = stakingState?.type === 'jetton'
    ? stakingState.unclaimedRewards
    : undefined;
  const loyaltyBalance = (stakingState?.type === 'liquid' ? stakingState.loyaltyBalance : 0n) ?? 0n;

  // Updates the unstaking countdown
  useInterval(forceUpdate, unstakeRequestAmount ? UPDATE_UNSTAKE_DATE_INTERVAL_MS : undefined);

  useEffect(() => {
    if (isActive) {
      fetchStakingHistory();
    }
  }, [fetchStakingHistory, isActive]);

  const handleStakeClick = useLastCallback(() => {
    onClose?.();
    startStaking();
  });

  const handleUnstakeClick = useLastCallback(() => {
    onClose?.();
    startUnstaking();
  });

  const handleClaimClick = useLastCallback(() => {
    onClose?.();
    startStakingClaim();
  });

  let stakingResult = '0';
  let balanceResult = '0';
  if (amount) {
    // Unlike the jetton rewards above, the loyalty bonus has no field of its own, so the tile is
    // the only place it can be seen. It is not held in the STAKED jetton and does not compound
    // with the rate, hence it is added to the year projection rather than multiplied by the yield.
    stakingResult = toBig(amount + loyaltyBalance, decimals).round(SHORT_FRACTION_DIGITS).toString();
    balanceResult = toBig(amount, decimals)
      .mul((annualYield / 100) + 1)
      .add(toBig(loyaltyBalance, decimals))
      .round(SHORT_FRACTION_DIGITS)
      .toString();
  }

  const handleCheckEligibility = useLastCallback(() => {
    void openUrl(ETHENA_ELIGIBILITY_CHECK_URL);
  });

  const [selectedToken, selectableTokens] = useTokenDropdown({
    tokenBySlug,
    states,
    shouldUseNominators,
    selectedStakingId: stakingId,
    isViewMode,
    shouldKeepActiveBlockedStates: true,
    baseCurrency,
    currencyRates,
  });

  function renderUnstakeDescription() {
    let text: string | TeactNode[] | undefined;

    if (unstakeTime) {
      let textKey = '$unstaking_when_receive_with_amount';

      if (stakingType === 'ethena') {
        textKey = '$unstaking_when_receive_with_amount_ethena';
      } else if (stakingType === 'nominators') {
        textKey = '$unstaking_when_receive';
      }

      text = lang(textKey, {
        time: (
          <strong>
            {formatRelativeHumanDateTime(lang.code, unstakeTime)}
          </strong>
        ),
        amount: (
          <strong>
            {formatCurrency(toDecimal(unstakeRequestAmount ?? 0n, decimals), symbol!).replace(' ', '\u00A0')}
          </strong>
        ),
      });
    }

    return (
      <div className={buildClassName(styles.unstakeTime, styles.unstakeTime_purple)}>
        <AnimatedIconWithPreview
          play={isActive}
          size={ANIMATED_STICKER_TINY_ICON_PX}
          className={styles.unstakeTimeIcon}
          nonInteractive
          noLoop={false}
          tgsUrl={ANIMATED_STICKERS_PATHS[appTheme].iconClockPurple}
          previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview.iconClockPurple}
        />
        <div>
          {text}
        </div>
      </div>
    );
  }

  function renderHistory() {
    return (
      <div className={styles.history}>
        {shouldRenderTotalAmount && (
          <div ref={totalAmountRef} className={styles.historyTotal}>
            {lang('$total', {
              value: (
                <span className={styles.historyTotalValue}>
                  {formatCurrency(toDecimal(totalProfit), TONCOIN.symbol)}
                </span>
              ),
            })}
          </div>
        )}
        <div className={styles.historyTitle}>{lang('Earning History')}</div>
        <div className={buildClassName(
          styles.historyList,
          height >= HISTORY_SCROLL_APPEARANCE_HEIGHT_PX && 'custom-scroll',
        )}
        >
          {stakingHistory?.map((record) => (
            <StakingProfitItem
              key={record.timestamp}
              profit={record.profit}
              timestamp={record.timestamp}
              tonToken={tonToken}
              isSensitiveDataHidden={isSensitiveDataHidden}
            />
          ))}
        </div>
      </div>
    );
  }

  const fullClassName = buildClassName(
    styles.stakingInfo,
    styles.stakingInfo_modal,
    !hasHistory && styles.stakingInfoNoHistory,
  );

  const handleChangeStaking = useLastCallback((id: string) => {
    onClose?.();

    changeCurrentStaking({ stakingId: id, shouldReopenModal: true });
  });

  function renderRewards() {
    const rewardString = toDecimal(unclaimedRewards!, decimals);

    return (
      <>
        <RichNumberField
          isSensitiveData
          isSensitiveDataHidden={isSensitiveDataHidden}
          sensitiveDataMaskSkin="purple"
          labelText={lang('Accumulated Rewards')}
          zeroValue="..."
          value={rewardString}
          decimals={decimals}
          suffix={symbol}
          className={styles.stakingBalance}
        />
        {!isViewMode && (
          <div className={styles.stakingInfoButtons}>
            <Button
              className={styles.stakingInfoButton}
              isDisabled={isLoading}
              onClick={handleClaimClick}
            >
              {lang('Claim')}
            </Button>
          </div>
        )}
      </>
    );
  }

  function render() {
    return (
      <>
        <div className={fullClassName}>
          <ModalHeader
            title={lang('Staking')}
            closeClassName={styles.stakingInfoClose}
            onClose={onClose}
          />

          <RichNumberField
            isSensitiveData
            isSensitiveDataHidden={isSensitiveDataHidden}
            sensitiveDataMaskSkin="purple"
            labelText={lang('Currently Staked')}
            zeroValue="..."
            value={stakingResult}
            decimals={decimals}
            className={styles.stakingBalance}
          >
            <div className={styles.stakingInfoLoading}>
              {shouldRenderSpinner && (
                <Spinner ref={spinnerRef} className={styles.stakingInfoLoadingAnimation} />
              )}
            </div>

            <TokenDropdown
              selectedToken={selectedToken}
              allTokens={selectableTokens}
              theme="purple"
              onChange={handleChangeStaking}
            />

          </RichNumberField>
          {unstakeRequestAmount && unstakeRequestAmount > 0n && stakingType !== 'ethena'
            ? renderUnstakeDescription()
            : (
              <>
                <RichNumberField
                  isSensitiveData
                  isSensitiveDataHidden={isSensitiveDataHidden}
                  sensitiveDataMaskSkin="purple"
                  labelText={lang('Est. balance in a year')}
                  zeroValue="..."
                  value={balanceResult}
                  decimals={decimals}
                  suffix={symbol}
                  className={styles.stakingBalance}
                />
                {stakingType === 'ethena' && !canBeClaimed && !!unstakeRequestAmount && renderUnstakeDescription()}
                {!isViewMode && (
                  <div
                    className={buildClassName(
                      styles.stakingInfoButtons,
                      stakingType === 'ethena' && styles.stakingInfoButtonsAdaptiveWidth,
                      !!unclaimedRewards && styles.stakingInfoButtonsWithMargin,
                    )}
                  >
                    {getIsNewStakeAllowed(tokenSlug) && (
                      <Button
                        className={styles.stakingInfoButton}
                        isPrimary
                        isDisabled={isLoading}
                        onClick={handleStakeClick}
                      >
                        {lang('Stake More')}
                      </Button>
                    )}
                    {(stakingType !== 'ethena' || !canBeClaimed) && (
                      <Button
                        className={styles.stakingInfoButton}
                        isDisabled={isLoading}
                        onClick={handleUnstakeClick}
                      >
                        {lang(stakingType === 'ethena' ? 'Request Unstaking' : 'Unstake')}
                      </Button>
                    )}
                    {canBeClaimed && (
                      <Button
                        className={styles.stakingInfoButton}
                        isDisabled={isLoading}
                        onClick={handleClaimClick}
                      >
                        {lang('Unstake %amount%', {
                          amount: isSensitiveDataHidden
                            ? `*** ${symbol}`
                            : formatCurrency(toDecimal(unstakeRequestAmount!, decimals), symbol!, FRACTION_DIGITS),
                        })}
                      </Button>
                    )}
                  </div>
                )}
                {!isViewMode && isEthenaBoostAvailable && (
                  <Button isText className={styles.checkEligibilityButton} onClick={handleCheckEligibility}>
                    {lang('Check eligibility for max APY')}
                  </Button>
                )}
                {!!unclaimedRewards && renderRewards()}
              </>
            )}
        </div>

        {hasHistory && renderHistory()}
      </>
    );
  }

  return (
    <Transition name="fade" activeKey={0} shouldCleanup>
      {render()}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const {
    settings: { theme, isSensitiveDataHidden },
    tokenInfo: { bySlug: tokenBySlug },
  } = global;
  const accountState = selectCurrentAccountState(global);

  const states = accountId ? selectAccountStakingStates(global, accountId) : undefined;
  const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;

  const stakingHistory = accountId ? selectAccountStakingHistory(global, accountId) : undefined;
  const totalProfit = accountId ? selectAccountStakingTotalProfit(global, accountId) : 0n;

  return {
    stakingState,
    states,
    totalProfit,
    stakingHistory,
    tokens: selectCurrentAccountTokens(global),
    tokenBySlug,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    theme,
    shouldUseNominators: accountState?.staking?.shouldUseNominators,
    isSensitiveDataHidden,
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(StakingInfoContent));
