import React, { memo, type TeactNode, useCallback, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiForeignStakingPromotion, ApiStakingState, ApiTokenWithPrice,
} from '../../api/types';
import type { UserToken } from '../../global/types';
import { StakingState } from '../../global/types';

import {
  DEFAULT_PRICE_CURRENCY,
  JVAULT_URL,
  TONCOIN,
} from '../../config';
import { getHelpCenterUrl } from '../../global/helpers/getHelpCenterUrl';
import renderText from '../../global/helpers/renderText';
import {
  selectAccountStakingState,
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountStakingBanners,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import { bigintMax } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { getTonStakingFees } from '../../util/fee/getTonOperationFees';
import { formatCurrency } from '../../util/formatNumber';
import { vibrate } from '../../util/haptics';
import { animateShift } from '../../util/layoutChangeAnimation';
import { openUrl } from '../../util/openUrl';
import { throttle } from '../../util/schedulers';
import { getStakingMinAmount, getStakingTitle } from '../../util/staking';
import { buildUserToken, getIsNativeToken, getNativeToken } from '../../util/tokens';
import calcJettonStakingApr from '../../util/ton/calcJettonStakingApr';
import { getHostnameFromUrl } from '../../util/url';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useFlag from '../../hooks/useFlag';
import useHeightChange from '../../hooks/useHeightChange';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import { useAmountInputState } from '../ui/hooks/useAmountInputState';
import { useTokenDropdown } from './hooks/useTokenDropdown';

import InfoBanner from '../common/InfoBanner';
import AmountInput from '../ui/AmountInput';
import Button from '../ui/Button';
import Fee from '../ui/Fee';
import Modal from '../ui/Modal';
import ModalFooter from '../ui/ModalFooter';
import Transition from '../ui/Transition';
import StakingDetails from './StakingDetails';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Staking.module.scss';

interface StateProps {
  isLoading?: boolean;
  isComplete?: boolean;
  isViewMode: boolean;
  apiError?: string;
  initialAmount?: bigint | 'all';
  tokens?: UserToken[];
  tokenBySlug?: Record<string, ApiTokenWithPrice>;
  stakingState?: ApiStakingState;
  states?: ApiStakingState[];
  shouldUseNominators?: boolean;
  isSensitiveDataHidden?: true;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingBanners?: ApiForeignStakingPromotion[];
  dismissedStakingBannerIds?: string[];
  isStakingBannerLoading: boolean;
}

const enum BottomRightSlide {
  Fee,
  InsufficientBalance,
  InsufficientFee,
  BelowMinimumAmount,
  ApiError,
}

const ACTIVE_STATES = new Set([StakingState.StakeInitial, StakingState.None]);

const runThrottled = throttle((cb) => cb(), 1500, true);

function StakingInitial({
  isLoading,
  isComplete,
  isViewMode,
  apiError,
  initialAmount,
  tokens,
  tokenBySlug,
  stakingState,
  states,
  shouldUseNominators,
  isSensitiveDataHidden,
  baseCurrency,
  currencyRates,
  stakingBanners,
  dismissedStakingBannerIds,
  isStakingBannerLoading,
}: StateProps) {
  const {
    submitStakingInitial,
    fetchStakingFee,
    cancelStaking,
    changeCurrentStaking,
    startForeignUnstake,
    dismissStakingBanner,
  } = getActions();

  const lang = useLang();

  const [isSafeInfoModalOpen, openSafeInfoModal, closeSafeInfoModal] = useFlag();
  const [amount, setAmount] = useState<bigint | undefined>(
    typeof initialAmount === 'bigint' ? initialAmount : undefined,
  );
  const [isInitialAmountApplied, setIsInitialAmountApplied] = useState(initialAmount !== 'all');
  let isIncorrectAmount = false;
  let isInsufficientBalance = false;
  let isInsufficientFee = false;
  let isBelowMinimumAmount = false;

  const {
    id: stakingId,
    type: stakingType,
    tokenSlug,
  } = stakingState ?? {};

  const token: UserToken | undefined = useMemo(() => {
    if (!tokenSlug || !tokens || !tokenBySlug) return undefined;
    let userToken = tokens.find(({ slug }) => slug === tokenSlug);
    if (!userToken && tokenSlug in tokenBySlug) {
      userToken = buildUserToken(tokenBySlug[tokenSlug]);
    }
    return userToken;
  }, [tokenSlug, tokens, tokenBySlug]);
  const { amount: balance = 0n, symbol, decimals = TONCOIN.decimals } = token ?? {};

  let { annualYield = 0 } = stakingState ?? {};
  let annualYieldText = `${annualYield}%`;
  if (stakingState?.type === 'jetton' && amount) {
    annualYield = calcJettonStakingApr({
      tvl: stakingState.tvl + amount,
      dailyReward: stakingState.dailyReward,
      decimals,
    });
    annualYieldText = `${annualYield}%`;
  } else if (stakingState?.type === 'ethena') {
    const { annualYieldStandard, annualYieldVerified, isBoostAvailable } = stakingState;
    annualYieldText = isBoostAvailable && annualYieldVerified !== undefined
      ? `${annualYieldStandard}%–${annualYieldVerified}%`
      : `${annualYieldStandard}%`;
  }

  const isNativeToken = getIsNativeToken(token?.slug);
  const nativeToken = useMemo(() => {
    if (!tokens || !token) return undefined;
    if (isNativeToken) return token;
    const nativeSlug = getNativeToken(token.chain).slug;
    return tokens.find(({ slug }) => slug === nativeSlug);
  }, [tokens, token, isNativeToken]);
  const nativeBalance = nativeToken?.amount ?? 0n;

  const minAmount = getStakingMinAmount(stakingType);

  const { gas: networkFee, real: realFee } = getTonStakingFees(stakingState?.type).stake;

  const nativeAmount = isNativeToken && amount ? amount + networkFee : networkFee;
  const doubleNetworkFee = networkFee * 2n;
  const shouldLeaveForUnstake = isNativeToken && balance >= doubleNetworkFee;
  const maxAmount = (() => {
    let value = balance;
    if (isNativeToken && value) {
      value -= shouldLeaveForUnstake ? doubleNetworkFee : networkFee;
    }
    return bigintMax(0n, value);
  })();

  useEffect(() => {
    if (isInitialAmountApplied || initialAmount !== 'all' || !token) return;
    setAmount(maxAmount);
    setIsInitialAmountApplied(true);
  }, [initialAmount, isInitialAmountApplied, maxAmount, token]);

  const title = getStakingTitle(stakingType);

  if (amount !== undefined) {
    if (Number.isNaN(amount) || amount < 0) {
      isIncorrectAmount = true;
    } else if (amount < minAmount) {
      isBelowMinimumAmount = true;
    } else if (!maxAmount || amount > balance) {
      isInsufficientBalance = true;
    } else if (nativeBalance < networkFee || (isNativeToken && nativeAmount > balance)) {
      isInsufficientFee = true;
    }
  }

  const [selectedToken, selectableTokens] = useTokenDropdown({
    tokenBySlug,
    states,
    shouldUseNominators,
    selectedStakingId: stakingId,
    baseCurrency,
    currencyRates,
  });

  const handleHelpCenterClick = useLastCallback(() => {
    const url = getHelpCenterUrl(lang.code, 'ethenaStaking');
    void openUrl(url, { title: lang('Help Center'), subtitle: getHostnameFromUrl(url) });
  });

  useEffect(() => {
    if (!amount) {
      return;
    }

    runThrottled(() => {
      fetchStakingFee({
        amount,
      });
    });
  }, [amount, fetchStakingFee]);

  const canSubmit = amount
    && maxAmount
    && !isViewMode
    && !isIncorrectAmount
    && !isBelowMinimumAmount
    && !isInsufficientFee
    && !isInsufficientBalance;

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);

    if (!canSubmit) {
      return;
    }

    vibrate();

    submitStakingInitial({ amount });
  });

  useEffect(() => {
    if (isComplete) setAmount(undefined);
  }, [isComplete]);

  const [error, errorTransitionKey] = useMemo(() => {
    if (isInsufficientBalance) {
      return [
        lang('Insufficient balance'),
        BottomRightSlide.InsufficientBalance,
      ];
    }

    if (isInsufficientFee) {
      return [
        lang('$insufficient_fee', { fee: formatCurrency(toDecimal(networkFee), nativeToken?.symbol ?? '') }),
        BottomRightSlide.InsufficientFee,
      ];
    }

    if (isBelowMinimumAmount) {
      return [
        lang('$min_value', { value: formatCurrency(toDecimal(minAmount, decimals), symbol ?? '') }),
        BottomRightSlide.BelowMinimumAmount,
      ];
    }

    return apiError
      ? [lang(apiError), BottomRightSlide.ApiError]
      : [undefined, BottomRightSlide.Fee];
  }, [
    apiError, decimals, isBelowMinimumAmount, isInsufficientBalance, isInsufficientFee, lang, minAmount,
    nativeToken?.symbol, networkFee, symbol,
  ]);

  // It is necessary to use useCallback instead of useLastCallback here
  const renderBottomRight = useCallback((className?: string) => {
    let content: string | TeactNode[] | React.JSX.Element;

    if (error) {
      content = (
        <span className={styles.balanceError}>{error}</span>
      );
    } else {
      content = token ? lang('$fee_value', {
        fee: <Fee terms={{ native: realFee }} precision="approximate" token={token} />,
      }) : '';
    }

    return (
      <Transition
        className={buildClassName(
          styles.amountBottomRight,
          isIncorrectAmount && styles.amountBottomRight_error,
          className,
        )}
        slideClassName={styles.amountBottomRight_slide}
        name="semiFade"
        activeKey={errorTransitionKey}
      >
        {content}
      </Transition>
    );
  }, [error, errorTransitionKey, isIncorrectAmount, lang, realFee, token]);

  function renderJettonDescription() {
    return (
      <>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_description_jetton1', {
            jvault_link: (
              <a href={JVAULT_URL} target="_blank" rel="noreferrer"><b>JVault</b></a>
            ),
          }))}
        </p>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_description_jetton2'))}
        </p>
      </>
    );
  }

  function renderTonDescription() {
    return (
      <>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_description1'))}
        </p>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_description2', { chain: getChainTitle('ton') }))}
        </p>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_description3'))}
        </p>
      </>
    );
  }

  function renderEthenaDescription() {
    return (
      <>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_ethena_description1'))}
        </p>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_ethena_description2'))}
        </p>
        <p className={modalStyles.text}>
          {renderText(lang('$safe_staking_ethena_description3'))}
        </p>
      </>
    );
  }

  function renderSafeDescription() {
    switch (stakingState!.type) {
      case 'jetton':
        return renderJettonDescription();

      case 'ethena':
        return renderEthenaDescription();

      default:
        return renderTonDescription();
    }
  }

  function renderSafeInfoModal() {
    return (
      <Modal
        isCompact
        isOpen={isSafeInfoModalOpen}
        title={lang(title)}
        onClose={closeSafeInfoModal}
        dialogClassName={styles.stakingSafeDialog}
      >
        {!!stakingState && renderSafeDescription()}
        <div className={modalStyles.buttons}>
          {stakingState!.type === 'ethena' && (
            <Button onClick={handleHelpCenterClick}>
              {lang('Help Center')}
            </Button>
          )}
          <Button onClick={closeSafeInfoModal}>{lang('Close')}</Button>
        </div>
      </Modal>
    );
  }

  const handleChangeStaking = useLastCallback((id: string) => {
    cancelStaking();

    changeCurrentStaking({ stakingId: id, shouldReopenModal: true });
  });

  const stakingBanner = useMemo(
    () => stakingBanners?.find(({ id }) => !dismissedStakingBannerIds?.includes(id)),
    [stakingBanners, dismissedStakingBannerIds],
  );
  const isStakingBannerShown = stakingBanner !== undefined
    && tokenSlug === getNativeToken(stakingBanner.foreignStaking.chain).slug;
  const renderedStakingBanner = useCurrentOrPrev(isStakingBannerShown ? stakingBanner : undefined, true);
  const stakingBannerRootRef = useRef<HTMLDivElement>();
  const amountAndDetailsRef = useRef<HTMLDivElement>();
  const amountAndDetailsTopRef = useRef<number>();

  // Measured at the end of the fade-out: the banner still holds its place, and the form slide is visible again
  const handleStakingBannerCloseAnimationEnd = useLastCallback(() => {
    const amountAndDetails = amountAndDetailsRef.current;
    // The close timer can fire after the modal has closed
    if (!amountAndDetails) return;

    amountAndDetailsTopRef.current = getTop(amountAndDetails);
  });

  const { ref: stakingBannerRef, shouldRender: shouldRenderStakingBanner } = useShowTransition({
    isOpen: isStakingBannerShown,
    noMountTransition: true,
    withShouldRender: true,
    className: 'slow',
    onCloseAnimationEnd: handleStakingBannerCloseAnimationEnd,
  });

  const handleStakingBannerActionClick = useLastCallback((id: string) => {
    startForeignUnstake({ id });
  });

  const handleStakingBannerClose = useLastCallback((id: string) => {
    dismissStakingBanner({ id });
  });

  // Measured rather than taken from the banner height, as the browser may also adjust the scroll position
  const handleStakingBannerRootHeightChange = useLastCallback(() => {
    const prevTop = amountAndDetailsTopRef.current;
    if (prevTop === undefined) return;

    amountAndDetailsTopRef.current = undefined;

    const amountAndDetails = amountAndDetailsRef.current!;
    animateShift(amountAndDetails, 0, prevTop - getTop(amountAndDetails));
  });

  useHeightChange(stakingBannerRootRef, handleStakingBannerRootHeightChange);

  const amountInputProps = useAmountInputState({
    amount,
    token,
    baseCurrency,
    onAmountChange: setAmount,
    onTokenChange: handleChangeStaking,
  });

  return (
    <form className={modalStyles.transitionContent} onSubmit={handleSubmit}>
      <div ref={stakingBannerRootRef}>
        {shouldRenderStakingBanner && (
          <div ref={stakingBannerRef} className={styles.foreignStakingBanner}>
            <InfoBanner
              banner={renderedStakingBanner!}
              isLoading={isStakingBannerLoading}
              isSensitiveDataHidden={isSensitiveDataHidden}
              onActionClick={handleStakingBannerActionClick}
              onClose={handleStakingBannerClose}
            />
          </div>
        )}
      </div>

      <div ref={amountAndDetailsRef}>
        <AmountInput
          {...amountInputProps}
          containerClassName={styles.amountInputContainer}
          maxAmount={maxAmount}
          token={selectedToken}
          allTokens={selectableTokens}
          hasError={isIncorrectAmount || isInsufficientBalance}
          isMaxAmountLoading={!selectedToken}
          isSensitiveDataHidden={isSensitiveDataHidden}
          renderBottomRight={renderBottomRight}
          onPressEnter={handleSubmit}
        />

        {!!stakingState && !!symbol && (
          <StakingDetails
            stakingState={stakingState}
            symbol={symbol}
            amount={amount}
            decimals={decimals}
            annualYieldText={annualYieldText}
            isBaseCurrency={amountInputProps.isBaseCurrency}
            token={token}
            baseCurrency={baseCurrency}
            onSafeInfoClick={openSafeInfoModal}
          />
        )}
      </div>

      {renderSafeInfoModal()}

      {!isViewMode && (
        <ModalFooter isFrosted>
          <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsNoExtraSpace)}>
            <Button
              isPrimary
              isSubmit
              isDisabled={!canSubmit}
              isLoading={isLoading}
              className={styles.submitButton}
            >
              {lang('$stake_asset', { symbol: token?.symbol })}
            </Button>
          </div>
        </ModalFooter>
      )}
    </form>
  );
}

export default memo(
  withGlobal(
    (global): StateProps => {
      const currentAccountId = selectCurrentAccountId(global);
      const accountState = selectCurrentAccountState(global);
      const tokens = selectCurrentAccountTokens(global);
      const tokenBySlug = global.tokenInfo.bySlug;

      const { baseCurrency = DEFAULT_PRICE_CURRENCY, isSensitiveDataHidden } = global.settings;

      const {
        state,
        isLoading,
        error: apiError,
        initialAmount,
      } = global.currentStaking;

      const states = currentAccountId ? selectAccountStakingStates(global, currentAccountId) : undefined;
      const stakingState = currentAccountId ? selectAccountStakingState(global, currentAccountId) : undefined;

      return {
        isViewMode: selectIsCurrentAccountViewMode(global),
        isLoading: isLoading && ACTIVE_STATES.has(state),
        isComplete: state === StakingState.StakeComplete,
        tokens,
        tokenBySlug,
        apiError,
        initialAmount,
        stakingState,
        states,
        shouldUseNominators: accountState?.staking?.shouldUseNominators,
        isSensitiveDataHidden,
        baseCurrency,
        currencyRates: global.currencyRates,
        stakingBanners: selectCurrentAccountStakingBanners(global),
        dismissedStakingBannerIds: global.currentStaking.dismissedBannerIds,
        isStakingBannerLoading: Boolean(global.currentStaking.foreignUnstake),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(StakingInitial),
);

function getTop(element: HTMLElement) {
  return element.getBoundingClientRect().top;
}
