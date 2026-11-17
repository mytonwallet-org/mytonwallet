import React, { memo, useMemo, useRef } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsAccountPosition, ApiPerpsFundingSource, ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';
import type { DropdownItem } from '../../ui/Dropdown';

import { ARBITRUM, ARBITRUM_USDC_MAINNET } from '../../../config';
import { Big } from '../../../lib/big.js';
import { hasPerpsAmount, isPerpsAmountEqual, isPerpsNumber } from '../../../global/helpers/perps';
import {
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsPosition,
  selectCurrentAccountState,
  selectCurrentAccountTokenBalance,
} from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';
import { toDecimal } from '../../../util/decimals';
import { stopEvent } from '../../../util/domEvents';
import { formatCurrency, formatPercent, formatSignedPercent } from '../../../util/formatNumber';
import { vibrate } from '../../../util/haptics';
import { animateContentShift, animateFadeIn } from '../../../util/layoutChangeAnimation';
import { floor } from '../../../util/round';
import {
  formatLeverage,
  formatPerpsMoney,
  formatPerpsQuantity,
  getPerpsAssetName,
  getPerpsErrorText,
} from '../helpers/formatPerps';

import useEffectWithPrevDeps from '../../../hooks/useEffectWithPrevDeps';
import useFlag from '../../../hooks/useFlag';
import useHeightChange from '../../../hooks/useHeightChange';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import usePerpsTradeQuotes from '../hooks/usePerpsTradeQuotes';

import TradeNotice from '../../swap/TradeNotice';
import TradePercentRow from '../../swap/TradePercentRow';
import Button from '../../ui/Button';
import AmountInput from './AmountInput';
import FormHeader from './FormHeader';
import FundingNotice, { getPerpsFundingBlock } from './FundingNotice';
import LeverageModal from './LeverageModal';
import UsdcRow from './UsdcRow';

import tradeStyles from '../../swap/TokenTrade.module.scss';
import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeForm.module.scss';

interface OwnProps {
  isActive: boolean;
  trade: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
}

interface StateProps {
  position?: ApiPerpsAccountPosition;
  usdcBalance: bigint;
  ethBalance: bigint;
  areBalancesLoaded: boolean;
  /** The USDC on the Hyperliquid balance that an order in the `dex` of the market can post as margin */
  spendableUsdc?: string;
}

const OPEN_FRACTIONS = [25, 50, 100];
// Changes of the current collateral
const EDIT_FRACTIONS = [-25, -5, 5, 25];
// A longer market name gives way to its ticker in the title
const MAX_TITLE_NAME_LENGTH = 12;
// The Hyperliquid balance becomes a payment option above this amount, as in the native apps
const MIN_BALANCE_FUNDING_USDC = 0.25;
const BALANCE_DECIMALS = 2;
const SCROLL_CONTAINER_SELECTOR = '.custom-scroll';

/** The form of a new position and of a change of an open one, where the amount is the collateral it gets */
function TradeForm({
  isActive, trade, asset, position, usdcBalance, ethBalance, areBalancesLoaded, spendableUsdc,
}: OwnProps & StateProps) {
  const {
    setPerpsTradeAmount, applyPerpsTradeFraction, resetPerpsTradeAmount, preparePerpsTrade,
    loadPerpsTradePreview, loadPerpsFundingRequirements, setPerpsTradeFundingSource,
  } = getActions();
  const lang = useLang();

  const topCardRef = useRef<HTMLDivElement>();
  const noticeRef = useRef<HTMLDivElement>();
  const bodyRef = useRef<HTMLDivElement>();
  const footerRef = useRef<HTMLDivElement>();

  const [isLeverageModalOpen, openLeverageModal, closeLeverageModal] = useFlag();

  const {
    kind, side, amount, leverage, preview, funding, fundingError, error, errorDetails, isPreparing, isPreviewLoading,
  } = trade;
  const isEdit = kind === 'edit';
  const symbol = asset?.symbol ?? '';
  const assetName = asset ? getPerpsAssetName(asset) : symbol;
  const isAmountChanged = isEdit && !isPerpsAmountEqual(amount, trade.currentAmount);
  const fundingBlock = useMemo(() => funding && getPerpsFundingBlock(lang, funding, isEdit), [lang, funding, isEdit]);

  usePerpsTradeQuotes(trade, isActive, usdcBalance, ethBalance, isLeverageModalOpen, Boolean(fundingBlock));
  const fractions = isEdit ? EDIT_FRACTIONS : OPEN_FRACTIONS;
  const availableCollateral = funding?.availableCollateral;
  const canUseFractions = !fundingBlock
    && (isEdit || (isPerpsNumber(availableCollateral) && Big(availableCollateral).gt(0)));
  const isChanged = !isEdit || isAmountChanged;
  const hasAmount = hasPerpsAmount(amount);
  // An unchanged position has nothing to review, as on iOS
  const canReview = Boolean(asset && preview && preview.kind !== 'unchanged')
    && !error && !fundingError && !fundingBlock && isChanged && hasAmount;
  const isIdle = !preview && !isPreviewLoading && !error && !fundingError;
  const hasNotice = Boolean(fundingBlock || error || fundingError);
  const isFromBalance = trade.fundingSource === 'balance';
  // A reduce returns the margin to the wallet. The typed amount reveals a reduce before the preview loads, as on
  // Android.
  const isReducing = isAmountChanged && isPerpsNumber(amount) && Big(amount).lt(trade.currentAmount!);
  // A chosen balance stays switchable after it falls below the minimum
  const canSelectFunding = !isReducing
    && (isFromBalance || (isPerpsNumber(spendableUsdc) && Big(spendableUsdc).gt(MIN_BALANCE_FUNDING_USDC)));

  const fundingItems = useMemo((): DropdownItem<ApiPerpsFundingSource>[] | undefined => {
    if (!canSelectFunding) return undefined;

    return [
      {
        value: 'wallet',
        name: getChainTitle('arbitrum'),
        // The wallet balance stays blank until the balances load
        description: areBalancesLoaded
          ? formatFundingBalance(toDecimal(usdcBalance, ARBITRUM_USDC_MAINNET.decimals))
          : undefined,
      },
      {
        value: 'balance',
        name: getChainTitle('hyperliquid'),
        description: formatFundingBalance(spendableUsdc),
      },
    ];
  }, [areBalancesLoaded, canSelectFunding, spendableUsdc, usdcBalance]);

  // A notice fades in, and the controls below the top card slide there from their old place when it changes the height
  // of the card. The button stays at the bottom of the form.
  useEffectWithPrevDeps(([prevHasNotice]) => {
    if (hasNotice && prevHasNotice === false) animateFadeIn(noticeRef.current!);
  }, [hasNotice]);

  const handleTopCardHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    for (
      let element = bodyRef.current!.firstElementChild;
      element && element !== footerRef.current;
      element = element.nextElementSibling
    ) {
      animateContentShift(element as HTMLElement, SCROLL_CONTAINER_SELECTOR, prevHeight - nextHeight);
    }
  });

  useHeightChange(topCardRef, handleTopCardHeightChange);

  const handleFundingRetry = useLastCallback(() => {
    loadPerpsFundingRequirements();
  });

  const handlePreviewRetry = useLastCallback(() => {
    loadPerpsTradePreview();
  });

  const handleAmountChange = useLastCallback((value?: string) => {
    setPerpsTradeAmount({ amount: value ?? '' });
  });

  const handleClearClick = useLastCallback(() => {
    setPerpsTradeAmount({ amount: '' });
  });

  const handleFundingSelect = useLastCallback((fundingSource: ApiPerpsFundingSource) => {
    setPerpsTradeFundingSource({ fundingSource });
  });

  const handleFractionClick = useLastCallback((fraction: number) => {
    vibrate();
    applyPerpsTradeFraction({ fraction });
  });

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);
    if (!canReview || isPreparing) return;

    vibrate();
    preparePerpsTrade();
  });

  function getTitle() {
    if (isEdit) return lang(side === 'long' ? '$perps_edit_long' : '$perps_edit_short', { asset: symbol }) as string;

    const titleName = assetName.length > MAX_TITLE_NAME_LENGTH ? symbol : assetName;

    return lang(side === 'long' ? '$perps_order_long' : '$perps_order_short', { asset: titleName }) as string;
  }

  // An error waits in a notice below the position details. A network failure of the estimate and a failed load of the
  // payment requirements can be retried, while any other error of the estimate stays until the form changes.
  function renderErrorNotice() {
    if (fundingBlock || (!error && !fundingError)) return undefined;

    const canRetry = !error || error === 'PerpsUnavailable';

    return (
      <TradeNotice
        ref={noticeRef}
        message={getPerpsErrorText(lang, error ?? fundingError, errorDetails)}
        actionTitle={canRetry ? lang('Retry') : undefined}
        className={buildClassName(styles.notice, styles.errorNotice)}
        onActionClick={error ? handlePreviewRetry : handleFundingRetry}
      />
    );
  }

  // The payment notice takes the place of the position details and the leverage, as the order waits for the funds
  function renderFundingNotice() {
    return (
      <div ref={noticeRef} className={buildClassName(styles.fundingNoticeSlot, isEdit && styles.edit)}>
        <FundingNotice block={fundingBlock!} />
      </div>
    );
  }

  function renderLeverageButton() {
    return (
      <button
        type="button"
        className={styles.leverageButton}
        onClick={openLeverageModal}
      >
        {lang('$perps_leverage_value', { value: formatLeverage(leverage) })}
        <i className={buildClassName(styles.leverageCaret, 'icon-expand')} aria-hidden />
      </button>
    );
  }

  // The figures of a new amount wait for its quote, while the current position shows its own
  function renderDetails() {
    const isCurrentPosition = isEdit && !isAmountChanged;
    const notional = preview?.notional ?? (isCurrentPosition ? position?.raw.positionValue : undefined);
    const positionSizeText = `${lang('Position Size')}: ${formatPerpsMoney(notional)}`;

    if (!isEdit) {
      return fundingBlock ? renderFundingNotice() : (
        <div className={styles.details}>
          {renderLeverageButton()}
          {notional !== undefined && <span className={styles.detailsText}>{positionSizeText}</span>}
        </div>
      );
    }

    const liquidationPrice = (isCurrentPosition ? position?.raw.liquidationPx : preview?.estimatedLiquidationPrice)
      ?? undefined;
    const liquidationText = `${lang('Liquidation')}: ${formatPerpsMoney(liquidationPrice)}`;

    return (
      <>
        {/* The line keeps its place while it is empty, so the details below do not move */}
        <div className={styles.current}>
          {isAmountChanged && (
            <>
              {lang('Current:')}{' '}
              <span className={styles.currentValue}>{formatPerpsMoney(trade.currentAmount)}</span>
            </>
          )}
        </div>
        {fundingBlock ? renderFundingNotice() : (
          <div className={buildClassName(styles.details, styles.detailsEdit)}>
            <span className={styles.detailsText}>{liquidationText}</span>
            <span className={styles.detailsText}>{positionSizeText}</span>
          </div>
        )}
      </>
    );
  }

  function getCoinText() {
    const size = preview?.size ?? (isEdit && !isAmountChanged ? position?.size : undefined);
    if (size !== undefined) return formatPerpsQuantity(symbol, size);

    // An empty field converts to zero coins, and a typed amount waits for its quote with the coins hidden
    return isIdle && !hasAmount ? formatPerpsQuantity(symbol, '0') : undefined;
  }

  function renderPayRow() {
    if (preview?.kind === 'reduce') {
      return <UsdcRow label={lang('You Receive')} amount={preview.estimatedReceiveAmount} isEstimated />;
    }

    const isPaying = !isEdit || preview?.kind === 'increase';

    return (
      <UsdcRow
        label={lang(isPaying ? 'You Pay' : 'You Pay or Receive')}
        amount={isPaying ? preview?.paymentAmount : undefined}
        isLabelMuted={!isPaying}
        fundingSource={trade.fundingSource}
        fundingItems={fundingItems}
        onFundingSelect={handleFundingSelect}
      />
    );
  }

  return (
    <>
      <form className={tradeStyles.form} onSubmit={handleSubmit}>
        <div ref={topCardRef} className={tradeStyles.topCard}>
          <FormHeader title={getTitle()} asset={asset} preview={preview} isEdit={isEdit} />
          <div className={tradeStyles.amountArea}>
            <AmountInput
              value={amount}
              coinText={getCoinText()}
              canReset={isAmountChanged}
              canClear={!isEdit}
              onChange={handleAmountChange}
              onSubmit={handleSubmit}
              onClear={handleClearClick}
              onReset={resetPerpsTradeAmount}
            />
            {renderDetails()}
            {renderErrorNotice()}
          </div>
        </div>
        <div ref={bodyRef} className={tradeStyles.body}>
          <TradePercentRow
            percents={fractions}
            isDisabled={!canUseFractions}
            formatPercent={isEdit ? formatSignedPercent : formatPercent}
            onSelect={handleFractionClick}
          />
          {renderPayRow()}
          <div ref={footerRef} className={tradeStyles.footer}>
            <Button
              isPrimary
              isSubmit
              isDisabled={!canReview}
              isLoading={isPreparing || (isPreviewLoading && !preview && !error)}
              className={modalStyles.buttonFullWidth}
            >
              {fundingBlock?.buttonText ?? lang('Review')}
            </Button>
          </div>
        </div>
      </form>
      {asset && !isEdit && (
        <LeverageModal isOpen={isLeverageModalOpen} trade={trade} asset={asset} onClose={closeLeverageModal} />
      )}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global, { trade, asset }): StateProps => {
  return {
    position: selectCurrentAccountPerpsPosition(global, trade.assetId),
    usdcBalance: selectCurrentAccountTokenBalance(global, ARBITRUM_USDC_MAINNET.slug),
    ethBalance: selectCurrentAccountTokenBalance(global, ARBITRUM.slug),
    areBalancesLoaded: Boolean(selectCurrentAccountState(global)?.balances),
    spendableUsdc: asset && selectCurrentAccountPerps(global)?.snapshot?.spendableUsdcByDex?.[asset.dex],
  };
})(TradeForm));

// Formats a balance for the payment menu. It is rounded down so that it never shows more than is available. A missing
// or non-numeric balance shows as zero.
function formatFundingBalance(value?: string) {
  const amount = value && Number.isFinite(Number(value)) ? value : 0;

  return formatCurrency(floor(amount, BALANCE_DECIMALS), ARBITRUM_USDC_MAINNET.symbol);
}
