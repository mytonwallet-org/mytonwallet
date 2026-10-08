import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiChain, ApiCurrencyRates } from '../../api/types';
import type { GlobalState, UserSwapToken } from '../../global/types';
import { SwapInputSource, SwapState, SwapType } from '../../global/types';

import { CURRENCIES } from '../../config';
import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectHasMultipleAccounts,
  selectSwapTokens,
  selectSwapType,
  selectTradeCardCurrencies,
} from '../../global/selectors';
import { bigintMultiplePercent } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { fromDecimal, toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import {
  formatCurrency, formatNumber, getIsCurrencySymbolAtStart, getShortCurrencySymbol,
} from '../../util/formatNumber';
import { vibrate } from '../../util/haptics';
import getSwapRate from '../../util/swap/getSwapRate';
import { getOnRampProvider } from '../main/modals/helpers/onRamp';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useOffRampMaxAmount from './hooks/useOffRampMaxAmount';
import useSwapEstimatePolling from './hooks/useSwapEstimatePolling';
import useSwapFormState from './hooks/useSwapFormState';
import useTradeAmountField from './hooks/useTradeAmountField';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import FiatCurrencyIcon from '../common/FiatCurrencyIcon';
import TokenIcon from '../common/TokenIcon';
import Button from '../ui/Button';
import FeeLine from '../ui/FeeLine';
import Modal from '../ui/Modal';
import RichNumberInput from '../ui/RichNumberInput';
import CexLegalDescription from './components/CexLegalDescription';
import SwapHint from './components/SwapHint';
import SwapSubmitButton from './components/SwapSubmitButton';
import TokenTradeMenu from './TokenTradeMenu';
import TokenTradeSlippageModal from './TokenTradeSlippageModal';

import modalStyles from '../ui/Modal.module.scss';
import hintStyles from './components/SwapHint.module.scss';
import styles from './TokenTrade.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  currentSwap: GlobalState['currentSwap'];
  tokens?: UserSwapToken[];
  swapType: SwapType;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  cardCurrencies: ApiBaseCurrency[];
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
}

const PERCENT_OPTIONS = [25, 50, 100];
const RAMP_PROVIDER_NAMES = { moonpay: 'MoonPay', avanchange: 'Avanchange' };

function TokenTrade({
  currentSwap,
  currentSwap: {
    tradeDirection,
    tradeCardCurrency,
    tradeAmount,
    isTradeAmountInToken,
    amountIn,
    amountOut,
    amountOutMin,
    inputSource,
    isEstimating,
    errorType,
    isLoading,
    limits,
    dieselStatus,
    priceImpact,
    slippage,
    currentCexProviderName,
    currentCexTermsOfUseUrl,
    currentCexPrivacyPolicyUrl,
    currentCexAmlKycPolicyUrl,
    swapHint,
  },
  tokens,
  swapType,
  baseCurrency,
  currencyRates,
  cardCurrencies,
  accountId,
  accountTitle,
  hasMultipleAccounts,
  isActive,
}: OwnProps & StateProps) {
  const {
    setTradeAmount,
    setTradeAmountUnit,
    setTradeCardCurrency,
    setSwapTokenOut,
    setSwapScreen,
    setSwapCexAddress,
    authorizeDiesel,
    cancelSwap,
    openOnRampWidgetModal,
    openOffRampWidgetModal,
    showDialog,
  } = getActions();
  const lang = useLang();

  const [isSlippageModalOpen, openSlippageModal, closeSlippageModal] = useFlag();
  const [isPriceImpactModalOpen, openPriceImpactModal, closePriceImpactModal] = useFlag();

  const isBuy = tradeDirection === 'buy';
  const isCardMode = Boolean(tradeCardCurrency);

  const {
    tokenIn,
    tokenOut,
    nativeUserTokenIn,
    explainedFee,
    maxAmount,
    isEnoughNative,
    isDieselNotAuthorized,
    canSubmit: canSubmitSwap,
    hasInsufficientFeeError,
    isPriceImpactError,
    isCrosschain,
  } = useSwapFormState(currentSwap, tokens, swapType);

  const screenToken = isBuy ? tokenOut : tokenIn;
  const counterToken = isBuy ? tokenIn : tokenOut;
  const screenChain = screenToken?.chain as ApiChain | undefined;

  const fieldCurrency = tradeCardCurrency ?? baseCurrency;
  const currencyDecimals = CURRENCIES[fieldCurrency].decimals;
  const currencySymbol = getShortCurrencySymbol(fieldCurrency);
  const price = screenToken ? calculateTokenPrice(screenToken.priceUsd, fieldCurrency, currencyRates) : 0;
  const hasPrice = price > 0;
  const isTokenUnit = Boolean(isTradeAmountInToken) || !hasPrice;

  useSwapEstimatePolling(currentSwap, isActive && !isCardMode);

  // The fiat currency can stop being offered: after a switch to an account without the chain, or when the
  // server narrows the allowed list. The screen then falls back to the counter token it still holds.
  useEffect(() => {
    if (tradeCardCurrency && !cardCurrencies.includes(tradeCardCurrency)) {
      setTradeCardCurrency({});
    }
  }, [tradeCardCurrency, cardCurrencies]);

  const handleAmountChange = useLastCallback((amount?: string) => {
    setTradeAmount({ amount });
  });

  const {
    inputValue,
    tokenAmount,
    currencyAmount,
    handleInputChange,
    applyTokenAmount,
    cancelPendingAmount,
  } = useTradeAmountField({
    tradeAmount,
    isTokenUnit,
    price,
    currencyDecimals,
    tokenDecimals: screenToken?.decimals,
    onAmountChange: handleAmountChange,
  });

  const cardMax = useOffRampMaxAmount({
    isActive: isCardMode && !isBuy,
    accountId,
    chain: screenChain,
    tokenSlug: screenToken?.slug,
    balance: screenToken?.amount,
  });

  const tokenAmountBigint = tokenAmount && screenToken ? fromDecimal(tokenAmount, screenToken.decimals) : 0n;
  // A percent of the paying balance becomes a screen amount only through the USD prices of both tokens
  const canConvertPercent = !isBuy || Boolean(tokenIn?.priceUsd && tokenOut?.priceUsd);
  const percentMaxAmount = isCardMode ? cardMax.amount : (canConvertPercent ? maxAmount : undefined);
  const shouldShowPercents = !(isCardMode && isBuy);

  const handlePercentClick = useLastCallback((percent: number) => {
    if (!percentMaxAmount || !screenToken || !tokenIn) return;

    vibrate();

    if (isCardMode) {
      const amount = toDecimal(bigintMultiplePercent(percentMaxAmount, percent), screenToken.decimals);
      applyTokenAmount(amount);
      setTradeAmount({ amount });
      return;
    }

    // The percent applies to the paying token. When buying, the screen amount is derived from it by the
    // reducer and arrives back through `tradeAmount`.
    const amount = toDecimal(bigintMultiplePercent(percentMaxAmount, percent), tokenIn.decimals);
    if (isBuy) {
      cancelPendingAmount();
    } else {
      applyTokenAmount(amount);
    }
    setTradeAmount({ amount, isMaxAmount: percent === 100, isAmountIn: true });
  });

  const handleClearClick = useLastCallback(() => {
    applyTokenAmount(undefined);
    setTradeAmount({ amount: undefined });
  });

  // The token to get first becomes the received one. When buying, it is the screen token, and the amount entered
  // for the previous token is cleared.
  const handleIntermediateHintClick = useLastCallback((tokenSlug: string) => {
    setSwapTokenOut({ tokenSlug });

    if (isBuy) {
      handleClearClick();
    }
  });

  const handleUnitToggle = useLastCallback(() => {
    vibrate();
    setTradeAmountUnit({ isInToken: !isTokenUnit });
  });

  const handleCounterClick = useLastCallback(() => {
    setSwapScreen({ state: isBuy ? SwapState.SelectTokenFrom : SwapState.SelectTokenTo });
  });

  const handleOpenAccountSelector = useLastCallback(() => {
    setSwapScreen({ state: SwapState.SelectAccount });
  });

  const handleProviderInfoClick = useLastCallback(() => {
    showDialog({
      title: lang('Cross-chain exchange provided by %provider%', currentCexProviderName!) as string,
      message: (
        <CexLegalDescription
          providerName={currentCexProviderName!}
          termsOfUseUrl={currentCexTermsOfUseUrl}
          privacyPolicyUrl={currentCexPrivacyPolicyUrl}
          amlKycPolicyUrl={currentCexAmlKycPolicyUrl}
        />
      ),
    });
  });

  const proceedToConfirmation = useLastCallback(() => {
    if (swapType === SwapType.CrosschainFromWallet) {
      setSwapCexAddress({ toAddress: '' });
      setSwapScreen({ state: SwapState.Blockchain });
    } else {
      setSwapScreen({ state: SwapState.Password });
    }
  });

  const handlePriceImpactConfirm = useLastCallback(() => {
    closePriceImpactModal();
    proceedToConfirmation();
  });

  let cardErrorText: string | undefined;
  let canSubmitCard = false;
  if (isCardMode) {
    if (!isBuy && cardMax.hasError) {
      cardErrorText = lang('Unexpected Error');
    } else if (!isBuy && cardMax.amount !== undefined && tokenAmountBigint > cardMax.amount) {
      cardErrorText = lang('Insufficient Balance');
    }
    canSubmitCard = !cardErrorText && (isBuy || !cardMax.isLoading);
  }
  const canSubmit = tokenAmountBigint > 0n && (isCardMode ? canSubmitCard : canSubmitSwap);
  const hint = !isCardMode && errorType !== undefined ? swapHint : undefined;
  const isPriceImpactWarningShown = !isCardMode && !isCrosschain && isPriceImpactError;

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);

    if (!canSubmit || !screenToken || !screenChain) {
      return;
    }

    if (isCardMode) {
      vibrate();

      if (isBuy) {
        openOnRampWidgetModal({ chain: screenChain, currency: tradeCardCurrency });
      } else {
        openOffRampWidgetModal({ chain: screenChain, currency: tradeCardCurrency, amount: tokenAmount });
      }
      cancelSwap({ shouldReset: true });
      return;
    }

    if (isDieselNotAuthorized) {
      authorizeDiesel();
      return;
    }

    vibrate();

    if (isPriceImpactError && !isCrosschain) {
      openPriceImpactModal();
      return;
    }

    proceedToConfirmation();
  });

  const exchangeRate = screenToken && (isCardMode
    ? `${screenToken.symbol} ≈ ${formatCurrency(price, currencySymbol, undefined, true)}`
    : buildSwapExchangeRate(tokenIn, tokenOut, amountIn, amountOut));

  const screenSymbol = screenToken?.symbol ?? '';
  let buttonLabel: string;
  if (tradeCardCurrency && screenChain) {
    const provider = RAMP_PROVIDER_NAMES[getOnRampProvider(screenChain, tradeCardCurrency)];
    buttonLabel = lang(isBuy ? 'Buy %token% via %provider%' : 'Sell %token% via %provider%', {
      token: screenSymbol,
      provider,
    }) as string;
  } else {
    buttonLabel = lang(isBuy ? 'Buy %token%' : 'Sell %symbol%', {
      token: screenSymbol,
      symbol: screenSymbol,
    }) as string;
  }

  function renderHeader() {
    return (
      <div className={styles.header}>
        {hasMultipleAccounts && accountId ? (
          <AccountSwitcherPill accountId={accountId} title={accountTitle} onClick={handleOpenAccountSelector} />
        ) : <span />}
        <div className={styles.headerButtons}>
          <TokenTradeMenu
            mode={isCardMode ? 'card' : isCrosschain ? 'cex' : 'dex'}
            exchangeRate={exchangeRate}
            priceImpact={priceImpact}
            isPriceImpactError={isPriceImpactError}
            minimumReceived={amountOutMin !== undefined && tokenOut
              ? formatCurrency(amountOutMin, tokenOut.symbol)
              : undefined}
            slippage={slippage}
            providerName={currentCexProviderName}
            onProviderInfoClick={handleProviderInfoClick}
            onSlippageClick={openSlippageModal}
          />
          <Button isRound className={styles.headerButton} ariaLabel={lang('Close')} onClick={cancelSwap}>
            <i className={buildClassName(styles.headerCloseIcon, 'icon-close')} aria-hidden />
          </Button>
        </div>
      </div>
    );
  }

  function renderUnitChip() {
    // While the paying amount is what the backend quotes against, the chip shows how much the quote buys
    const isQuoted = isBuy && !isCardMode && inputSource === SwapInputSource.In && Boolean(tokenAmount);
    const quotedTokenAmount = isQuoted ? amountOut : undefined;
    const isQuoteLoading = isQuoted && Boolean(isEstimating);
    const text = isTokenUnit
      ? `≈ ${formatCurrency(currencyAmount ?? '0', currencySymbol)}`
      : formatCurrency(quotedTokenAmount ?? tokenAmount ?? '0', screenSymbol);

    return (
      <button
        type="button"
        className={styles.unitChip}
        disabled={!hasPrice}
        aria-label={lang('Switch Amount Currency')}
        onClick={handleUnitToggle}
      >
        <span className={buildClassName(styles.unitChipText, isQuoteLoading && styles.loading)}>{text}</span>
        <i className={buildClassName(styles.unitChipIcon, 'icon-switch')} aria-hidden />
      </button>
    );
  }

  function renderAmountField() {
    const isSymbolAtStart = getIsCurrencySymbolAtStart(currencySymbol);
    const prefix = !isTokenUnit && isSymbolAtStart ? currencySymbol : '';
    const suffix = isTokenUnit ? screenSymbol : (isSymbolAtStart ? '' : currencySymbol);

    return (
      <div className={styles.amountRow}>
        <RichNumberInput
          id="token-trade-amount"
          value={inputValue}
          prefix={prefix}
          suffix={suffix}
          decimals={isTokenUnit ? screenToken?.decimals : currencyDecimals}
          className={styles.amountInput}
          inputClassName={styles.amountInputWrapper}
          valueClassName={styles.amountValue}
          onChange={handleInputChange}
          onPressEnter={handleSubmit}
        />
        {Boolean(inputValue) && (
          <button type="button" className={styles.clearButton} aria-label={lang('Clear')} onClick={handleClearClick}>
            <i className="icon-close-filled" aria-hidden />
          </button>
        )}
      </div>
    );
  }

  function renderFee() {
    const fee = explainedFee.realFee ?? explainedFee.fullFee;
    const shouldShow = !isCardMode && Boolean(tokenAmount) && fee && tokenIn;

    return (
      <FeeLine
        terms={shouldShow ? fee.networkTerms : undefined}
        token={tokenIn}
        precision={fee?.precision ?? 'exact'}
        isError={hasInsufficientFeeError}
        className={styles.feeLine}
      />
    );
  }

  function renderPriceImpactWarning() {
    return (
      <div className={buildClassName(
        hintStyles.root,
        hintStyles.trade,
        hintStyles.warning,
        styles.priceImpactWarning,
      )}
      >
        <div className={hintStyles.text}>
          <span className={hintStyles.title}>
            {lang('The exchange rate is below market value!', { value: `${priceImpact}%` })}
          </span>
          <span className={hintStyles.message}>
            {lang('We do not recommend to perform an exchange, try to specify a lower amount.')}
          </span>
        </div>
      </div>
    );
  }

  function renderPercentButtons() {
    return (
      <div className={styles.percentRow}>
        {PERCENT_OPTIONS.map((percent) => (
          <button
            key={percent}
            type="button"
            className={styles.percentButton}
            disabled={!percentMaxAmount}
            onClick={() => handlePercentClick(percent)}
          >
            {percent}%
          </button>
        ))}
      </div>
    );
  }

  function renderCounterRow() {
    let rowAmount: string | undefined;
    let rowSymbol: string | undefined;
    let isRowLoading = false;

    if (isCardMode) {
      rowAmount = currencyAmount;
      rowSymbol = tradeCardCurrency;
    } else if (isBuy) {
      rowAmount = amountIn;
      rowSymbol = tokenIn?.symbol;
      isRowLoading = Boolean(isEstimating && inputSource === SwapInputSource.Out);
    } else {
      rowAmount = amountOut;
      rowSymbol = tokenOut?.symbol;
      isRowLoading = Boolean(isEstimating && inputSource === SwapInputSource.In);
    }

    return (
      <button type="button" className={styles.counterRow} onClick={handleCounterClick}>
        {tradeCardCurrency ? (
          <FiatCurrencyIcon currency={tradeCardCurrency} size="small" className={styles.counterIcon} />
        ) : counterToken && (
          <TokenIcon
            token={counterToken}
            withChainIcon
            className={styles.counterIcon}
            iconClassName={styles.counterIconImage}
          />
        )}
        <span className={styles.counterLabel}>{lang(isBuy ? 'You Pay' : 'You Receive')}</span>
        <span className={styles.counterValue}>
          {Boolean(tokenAmount && rowAmount) && (
            <span className={buildClassName(styles.counterAmount, isRowLoading && styles.loading)}>
              {formatNumber(rowAmount!)}
            </span>
          )}
          <span className={styles.counterSymbol}>{rowSymbol ?? lang('Select Token')}</span>
          {!tradeCardCurrency && counterToken?.label && (
            <span className={styles.counterBadge}>{counterToken.label}</span>
          )}
          <i className={buildClassName(styles.counterCaret, 'icon-expand')} aria-hidden />
        </span>
      </button>
    );
  }

  return (
    <>
      <form className={styles.form} onSubmit={handleSubmit}>
        <div className={styles.topCard}>
          {renderHeader()}
          <div className={styles.amountArea}>
            <div className={styles.amountBlock}>
              {renderUnitChip()}
              {renderAmountField()}
            </div>
            {hint ? (
              <SwapHint
                hint={hint}
                tokens={tokens}
                tokenOut={tokenOut}
                tradeDirection={tradeDirection}
                className={styles.hint}
                onIntermediateClick={handleIntermediateHintClick}
              />
            ) : renderFee()}
            {isPriceImpactWarningShown && renderPriceImpactWarning()}
          </div>
        </div>
        <div className={styles.body}>
          {shouldShowPercents && renderPercentButtons()}
          {renderCounterRow()}
          <div className={styles.footer}>
            <SwapSubmitButton
              tokenIn={tokenIn}
              tokenOut={tokenOut}
              amountIn={amountIn}
              amountOut={amountOut}
              swapType={swapType}
              isEstimating={isCardMode ? !isBuy && cardMax.isLoading : isEstimating}
              isNotEnoughNative={!isCardMode && !isEnoughNative}
              nativeToken={nativeUserTokenIn}
              dieselStatus={isCardMode ? undefined : dieselStatus}
              isSending={isLoading}
              isPriceImpactError={!isCardMode && isPriceImpactError}
              canSubmit={canSubmit}
              errorType={isCardMode ? undefined : errorType}
              limits={limits}
              label={buttonLabel}
              errorText={cardErrorText}
              kind={isBuy ? 'green' : 'red'}
            />
          </div>
        </div>
      </form>
      <TokenTradeSlippageModal isOpen={isSlippageModalOpen} slippage={slippage} onClose={closeSlippageModal} />
      <Modal
        isOpen={isPriceImpactModalOpen}
        isCompact
        title={lang('The exchange rate is below market value!', { value: `${priceImpact ?? 0}%` })}
        titleClassName={styles.priceImpactModalTitle}
        onClose={closePriceImpactModal}
      >
        <p className={modalStyles.text}>
          {lang('We do not recommend to perform an exchange, try to specify a lower amount.')}
        </p>
        <div className={modalStyles.buttons}>
          <Button className={modalStyles.button} onClick={closePriceImpactModal}>{lang('Cancel')}</Button>
          <Button isDestructive className={modalStyles.button} onClick={handlePriceImpactConfirm}>
            {lang('Swap')}
          </Button>
        </div>
      </Modal>
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const account = selectCurrentAccount(global);

      return {
        currentSwap: global.currentSwap,
        tokens: selectSwapTokens(global),
        swapType: selectSwapType(global),
        baseCurrency: global.settings.baseCurrency,
        currencyRates: global.currencyRates,
        cardCurrencies: selectTradeCardCurrencies(global),
        accountId: selectCurrentAccountId(global),
        accountTitle: account?.title,
        hasMultipleAccounts: selectHasMultipleAccounts(global),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(TokenTrade),
);

/** Before the first quote arrives, the rate is taken from the token prices */
function buildSwapExchangeRate(
  tokenIn?: UserSwapToken,
  tokenOut?: UserSwapToken,
  amountIn?: string,
  amountOut?: string,
) {
  const priceRate = tokenIn?.priceUsd && tokenOut?.priceUsd
    ? String(tokenIn.priceUsd / tokenOut.priceUsd)
    : undefined;
  const rate = getSwapRate(amountIn, amountOut, tokenIn, tokenOut, true)
    ?? (priceRate ? getSwapRate('1', priceRate, tokenIn, tokenOut, true) : undefined);

  return rate && `${rate.firstCurrencySymbol} ≈ ${rate.price} ${rate.secondCurrencySymbol}`;
}
