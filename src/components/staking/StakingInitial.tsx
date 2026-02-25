import React, { memo, type TeactNode, useCallback, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState, ApiTokenWithPrice } from '../../api/types';
import type { UserToken } from '../../global/types';
import type { Big } from '../../lib/big.js';
import { StakingState } from '../../global/types';

import {
  ANIMATED_STICKER_MIDDLE_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  CURRENCIES,
  DEFAULT_PRICE_CURRENCY,
  ETHENA_ELIGIBILITY_CHECK_URL,
  JVAULT_URL,
  SHORT_FRACTION_DIGITS,
  TONCOIN,
} from '../../config';
import { getHelpCenterUrl } from '../../global/helpers/getHelpCenterUrl';
import renderText from '../../global/helpers/renderText';
import {
  selectAccountStakingState,
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import { bigintMax } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import { toBig, toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { getTonStakingFees } from '../../util/fee/getTonOperationFees';
import { formatCurrency } from '../../util/formatNumber';
import { vibrate } from '../../util/haptics';
import { openUrl } from '../../util/openUrl';
import { throttle } from '../../util/schedulers';
import { getStakingMinAmount, getStakingTitle } from '../../util/staking';
import { buildUserToken, getIsNativeToken, getNativeToken } from '../../util/tokens';
import calcJettonStakingApr from '../../util/ton/calcJettonStakingApr';
import { getHostnameFromUrl } from '../../util/url';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useAmountInputState } from '../ui/hooks/useAmountInputState';
import { useTokenDropdown } from './hooks/useTokenDropdown';

import AmountInput from '../ui/AmountInput';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Fee from '../ui/Fee';
import Modal from '../ui/Modal';
import RichNumberField from '../ui/RichNumberField';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Staking.module.scss';

interface OwnProps {
  isActive?: boolean;
  isStatic?: boolean;
}

interface StateProps {
  isLoading?: boolean;
  isComplete?: boolean;
  isViewMode: boolean;
  apiError?: string;
  tokens?: UserToken[];
  tokenBySlug?: Record<string, ApiTokenWithPrice>;
  stakingState?: ApiStakingState;
  states?: ApiStakingState[];
  shouldUseNominators?: boolean;
  isSensitiveDataHidden?: true;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
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
  isActive,
  isStatic,
  isLoading,
  isComplete,
  isViewMode,
  apiError,
  tokens,
  tokenBySlug,
  stakingState,
  states,
  shouldUseNominators,
  isSensitiveDataHidden,
  baseCurrency,
  currencyRates,
}: OwnProps & StateProps) {
  const {
    submitStakingInitial, fetchStakingFee, cancelStaking, changeCurrentStaking,
  } = getActions();

  const lang = useLang();

  const [isSafeInfoModalOpen, openSafeInfoModal, closeSafeInfoModal] = useFlag();
  const [amount, setAmount] = useState<bigint | undefined>();
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
  } else if (stakingState?.type === 'ethena') {
    const { annualYieldStandard, annualYieldVerified } = stakingState;
    annualYieldText = `${annualYieldStandard}%–${annualYieldVerified}%`;
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

  const title = getStakingTitle();

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

    void vibrate();

    submitStakingInitial({ amount });
  });

  useEffect(() => {
    if (isComplete) setAmount(undefined);
  }, [isComplete]);

  const handleCheckEligibility = useLastCallback(() => {
    void openUrl(ETHENA_ELIGIBILITY_CHECK_URL);
  });

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

  function renderStakingResult() {
    const amountBig = toBig(amount ?? 0, decimals);
    let currentAmount: Big;
    let prefix: string | undefined;
    let suffix: string | undefined;

    if (amountInputProps.isBaseCurrency) {
      currentAmount = amountBig.mul(token?.price ?? 0);
      const { shortSymbol } = CURRENCIES[baseCurrency];
      if (shortSymbol) {
        prefix = shortSymbol;
      } else {
        suffix = baseCurrency;
      }
    } else {
      currentAmount = amountBig;
    }

    const balanceResult = currentAmount.mul((annualYield / 100) + 1).toString();

    return (
      <Transition
        activeKey={amountInputProps.isBaseCurrency ? 0 : 1}
        name="semiFade"
        className={styles.balanceResultWrapper}
        slideClassName={styles.balanceResultWrapper__slide}
        shouldCleanup
      >
        <RichNumberField
          labelText={lang('Est. balance in a year')}
          zeroValue="..."
          value={balanceResult}
          decimals={SHORT_FRACTION_DIGITS}
          prefix={prefix}
          suffix={suffix}
          isStatic={isStatic}
          inputClassName={styles.balanceResultInput}
          labelClassName={styles.balanceResultLabel}
          valueClassName={styles.balanceResult}
        />
      </Transition>
    );
  }

  const handleChangeStaking = useLastCallback((id: string) => {
    cancelStaking();

    changeCurrentStaking({ stakingId: id, shouldReopenModal: !isStatic });
  });

  const amountInputProps = useAmountInputState({
    amount,
    token,
    baseCurrency,
    onAmountChange: setAmount,
    onTokenChange: handleChangeStaking,
  });

  return (
    <form
      className={isStatic ? undefined : modalStyles.transitionContent}
      onSubmit={handleSubmit}
    >
      <div className={buildClassName(styles.welcome, isStatic && styles.welcome_static)}>
        <AnimatedIconWithPreview
          size={isStatic ? ANIMATED_STICKER_MIDDLE_SIZE_PX : ANIMATED_STICKER_SMALL_SIZE_PX}
          play={isActive}
          noLoop={false}
          nonInteractive
          className={buildClassName(styles.sticker, isStatic && styles.sticker_static)}
          tgsUrl={ANIMATED_STICKERS_PATHS.wait}
          previewUrl={ANIMATED_STICKERS_PATHS.waitPreview}
        />
        <div className={buildClassName(styles.welcomeInformation, isStatic && styles.welcomeInformation_static)}>
          <div>{lang('Earn from your tokens while holding them', { symbol })}</div>
          <div className={styles.stakingApy}>{lang('Est. %annual_yield%', { annual_yield: annualYieldText })}</div>
          {stakingType === 'ethena' && (
            <Button isText className={styles.textButton} onClick={handleCheckEligibility}>
              {lang('Check eligibility')}
            </Button>
          )}
          <Button isText className={styles.textButton} onClick={openSafeInfoModal}>
            {lang(getStakingTitle(stakingType))}
          </Button>
        </div>
      </div>

      <AmountInput
        {...amountInputProps}
        maxAmount={maxAmount}
        token={selectedToken}
        allTokens={selectableTokens}
        isStatic={isStatic}
        hasError={isIncorrectAmount || isInsufficientBalance}
        isMaxAmountLoading={!selectedToken}
        isSensitiveDataHidden={isSensitiveDataHidden}
        renderBottomRight={renderBottomRight}
        onPressEnter={handleSubmit}
      />

      {renderStakingResult()}

      {!isViewMode && (
        <div className={modalStyles.buttons}>
          <Button
            isPrimary
            isSubmit
            isDisabled={!canSubmit}
            isLoading={isLoading}
          >
            {lang('$stake_asset', { symbol: token?.symbol })}
          </Button>
        </div>
      )}
      {renderSafeInfoModal()}
    </form>
  );
}

export default memo(
  withGlobal<OwnProps>(
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
        stakingState,
        states,
        shouldUseNominators: accountState?.staking?.shouldUseNominators,
        isSensitiveDataHidden,
        baseCurrency,
        currencyRates: global.currencyRates,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(StakingInitial),
);
