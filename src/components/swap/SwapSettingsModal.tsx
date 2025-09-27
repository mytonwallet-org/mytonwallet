import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiSwapAsset } from '../../api/types';
import type { DieselStatus } from '../../global/types';
import { SwapType } from '../../global/types';

import { DEFAULT_OUR_SWAP_FEE } from '../../config';
import renderText from '../../global/helpers/renderText';
import {
  selectCurrentAccountTokenBalance,
  selectCurrentSwapTokenIn,
  selectCurrentSwapTokenOut,
  selectSwapType,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { explainSwapFee } from '../../util/fee/swapFee';
import { formatCurrency } from '../../util/formatNumber';
import getSwapRate from '../../util/swap/getSwapRate';
import { findNativeToken, getChainBySlug } from '../../util/tokens';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Fee from '../ui/Fee';
import IconWithTooltip from '../ui/IconWithTooltip';
import Modal from '../ui/Modal';
import RichNumberInput from '../ui/RichNumberInput';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

interface OwnProps {
  isOpen: boolean;
  showFullNetworkFee?: boolean;
  onClose: () => void;
  onNetworkFeeClick?: () => void;
}

interface StateProps {
  amountIn?: string;
  amountOut?: string;
  tokenIn?: ApiSwapAsset;
  tokenOut?: ApiSwapAsset;
  networkFee?: string;
  realNetworkFee?: string;
  swapType: SwapType;
  slippage: number;
  priceImpact?: number;
  amountOutMin?: string;
  ourFee?: string;
  ourFeePercent?: number;
  dieselStatus?: DieselStatus;
  dieselFee?: string;
  nativeTokenInBalance?: bigint;
}

const SLIPPAGE_VALUES = [0.5, 1, 2, 5, 10];
const MAX_SLIPPAGE_VALUE = 50;

export const MAX_PRICE_IMPACT_VALUE = 5;

function SwapSettingsContent({
  onClose,
  amountIn,
  amountOut,
  swapType,
  tokenIn,
  tokenOut,
  slippage,
  priceImpact,
  networkFee,
  realNetworkFee,
  amountOutMin,
  ourFee,
  ourFeePercent = DEFAULT_OUR_SWAP_FEE,
  dieselStatus,
  dieselFee,
  nativeTokenInBalance,
  showFullNetworkFee,
  onNetworkFeeClick,
}: Omit<OwnProps, 'isOpen'> & StateProps) {
  const { setSlippage } = getActions();
  const lang = useLang();
  const canEditSlippage = swapType === SwapType.OnChain;

  // In order to reset this state when the modal is closed, we rely on the fact that Modal unmounts the content when
  // it's closed.
  const [currentSlippage, setCurrentSlippage] = useState<number | undefined>(slippage);

  const priceImpactError = (priceImpact ?? 0) >= MAX_PRICE_IMPACT_VALUE;
  const slippageError = currentSlippage === undefined
    ? 'Slippage not specified'
    : currentSlippage > MAX_SLIPPAGE_VALUE
      ? 'Slippage too high'
      : '';

  const handleSave = useLastCallback(() => {
    setSlippage({ slippage: currentSlippage! });
    onClose();
  });

  const handleInputChange = useLastCallback((stringValue?: string) => {
    const value = stringValue ? Number(stringValue) : undefined;
    setCurrentSlippage(value);
  });

  const explainedFee = useMemo(
    () => explainSwapFee({
      swapType,
      tokenInSlug: tokenIn?.slug,
      networkFee,
      realNetworkFee,
      ourFee,
      dieselStatus,
      dieselFee,
      nativeTokenInBalance,
    }),
    [swapType, tokenIn, networkFee, realNetworkFee, ourFee, dieselStatus, dieselFee, nativeTokenInBalance],
  );

  function renderSlippageValues() {
    const slippageList = SLIPPAGE_VALUES.map((value, index) => {
      return (
        <div key={value} className={styles.advancedSlippageButton}>
          <div
            role="button"
            tabIndex={0}
            onClick={() => setCurrentSlippage(value)}
            className={styles.balanceLink}
          >{value}%
          </div>
          {index + 1 !== SLIPPAGE_VALUES.length && <i className={styles.dot} aria-hidden />}
        </div>
      );
    });

    return (
      <div className={styles.advancedSlippageContainer}>
        <span className={styles.advancedSlippage}>{slippageList}</span>
      </div>
    );
  }

  function renderSlippageError() {
    return (
      <div className={styles.advancedSlippageError}>
        <span>{lang(slippageError)}</span>
      </div>
    );
  }

  function renderRate() {
    const rate = getSwapRate(
      amountIn,
      amountOut,
      tokenIn,
      tokenOut,
      true,
    );

    return (
      <div className={styles.advancedRow}>
        <span className={styles.advancedDescription}>
          {lang('Exchange Rate')}
        </span>
        <span className={styles.advancedValue}>
          {rate
            ? `${rate.firstCurrencySymbol} ≈ ${rate.price} ${rate.secondCurrencySymbol}`
            : <ValuePlaceholder />}
        </span>
      </div>
    );
  }

  function renderNetworkFee() {
    const actualFee = showFullNetworkFee ? explainedFee.fullFee : explainedFee.realFee;
    let feeElement = actualFee && tokenIn && (
      <Fee
        terms={actualFee.networkTerms}
        precision={actualFee.precision}
        token={tokenIn}
      />
    );

    if (feeElement && onNetworkFeeClick) {
      feeElement = (
        <span
          role="button"
          tabIndex={0}
          className={styles.advancedLink}
          onClick={() => onNetworkFeeClick()}
        >
          <span>{feeElement}</span>
          <i className={buildClassName('icon-chevron-right', styles.advancedLinkIcon)} aria-hidden />
        </span>
      );
    }

    return (
      <div className={styles.advancedRow}>
        <span className={styles.advancedDescription}>
          {lang('Blockchain Fee')}
        </span>
        <span className={styles.advancedValue}>
          {feeElement || <ValuePlaceholder />}
        </span>
      </div>
    );
  }

  function renderSlippageLabel() {
    return (
      <>
        {lang('Slippage')}
        <Tooltip isError={Boolean(slippageError)}>
          <span>{lang('$swap_slippage_tooltip1')}</span>
          <span>{lang('$swap_slippage_tooltip2')}</span>
        </Tooltip>
      </>
    );
  }

  return (
    <>
      {canEditSlippage && (
        <div className={styles.advancedInput}>
          {renderSlippageValues()}
          <RichNumberInput
            labelText={renderSlippageLabel()}
            labelClassName={styles.slippageLabel}
            value={currentSlippage?.toString()}
            hasError={Boolean(slippageError)}
            decimals={2}
            suffix="%"
            size="normal"
            onChange={handleInputChange}
          />
          {renderSlippageError()}
        </div>
      )}
      <div className={styles.advancedBlock}>
        {renderRate()}
        {renderNetworkFee()}

        {explainedFee.shouldShowOurFee && (
          <div className={styles.advancedRow}>
            <span className={styles.advancedDescription}>
              {lang('Aggregator Fee')}
              <Tooltip>
                <span>{renderText(lang('$swap_aggregator_fee_tooltip', { percent: `${ourFeePercent}%` }))}</span>
              </Tooltip>
            </span>
            <span className={styles.advancedValue}>
              {ourFee !== undefined
                ? formatCurrency(ourFee, tokenIn?.symbol ?? '', undefined, true)
                : <ValuePlaceholder />}
            </span>
          </div>
        )}
        {swapType === SwapType.OnChain && (
          <>
            <div className={styles.advancedRow}>
              <span className={buildClassName(styles.advancedDescription, priceImpactError && styles.advancedError)}>
                {lang('Price Impact')}
                <Tooltip isError={Boolean(priceImpactError)}>
                  <span>{lang('$swap_price_impact_tooltip1')}</span>
                  <span>{lang('$swap_price_impact_tooltip2')}</span>
                </Tooltip>
              </span>
              <span className={buildClassName(styles.advancedValue, priceImpactError && styles.advancedError)}>
                {priceImpact !== undefined ? `${priceImpact}%` : <ValuePlaceholder />}
              </span>
            </div>
            <div className={styles.advancedRow}>
              <span className={styles.advancedDescription}>
                {lang('Minimum Received')}
                <Tooltip>
                  <span>{lang('$swap_minimum_received_tooltip1')}</span>
                  <span>{lang('$swap_minimum_received_tooltip2')}</span>
                </Tooltip>
              </span>
              <span className={styles.advancedValue}>
                {amountOutMin !== undefined && tokenOut
                  ? formatCurrency(amountOutMin, tokenOut.symbol)
                  : <ValuePlaceholder />}
              </span>
            </div>
          </>
        )}
      </div>
      <div className={modalStyles.buttons}>
        <Button
          className={modalStyles.button}
          onClick={onClose}
        >
          {lang('Close')}
        </Button>
        {canEditSlippage && (
          <Button
            isPrimary
            isDisabled={Boolean(slippageError)}
            className={modalStyles.button}
            onClick={handleSave}
          >
            {lang('Save')}
          </Button>
        )}
      </div>
    </>
  );
}

const SwapSettings = memo(
  withGlobal<Omit<OwnProps, 'isOpen'>>((global): StateProps => {
    const {
      tokenInSlug,
      amountIn,
      amountOut,
      networkFee,
      realNetworkFee,
      slippage,
      priceImpact,
      amountOutMin,
      ourFee,
      ourFeePercent,
      dieselStatus,
      dieselFee,
    } = global.currentSwap;

    const nativeToken = tokenInSlug ? findNativeToken(getChainBySlug(tokenInSlug)) : undefined;
    const nativeTokenInBalance = nativeToken ? selectCurrentAccountTokenBalance(global, nativeToken.slug) : undefined;

    return {
      amountIn,
      amountOut,
      networkFee,
      realNetworkFee,
      swapType: selectSwapType(global),
      tokenIn: selectCurrentSwapTokenIn(global),
      tokenOut: selectCurrentSwapTokenOut(global),
      slippage,
      priceImpact,
      amountOutMin,
      ourFee,
      ourFeePercent,
      dieselStatus,
      dieselFee,
      nativeTokenInBalance,
    };
  })(SwapSettingsContent),
);

export default function SwapSettingsModal({ isOpen, onClose, ...restProps }: OwnProps) {
  const lang = useLang();

  return (
    <Modal isOpen={isOpen} onClose={onClose} isCompact title={lang('Swap Details')}>
      <SwapSettings onClose={onClose} {...restProps} />
    </Modal>
  );
}

function ValuePlaceholder() {
  const lang = useLang();
  return <span className={styles.advancedPlaceholder}>{lang('No Data')}</span>;
}

function Tooltip({ children, isError }: { children: TeactNode; isError?: boolean }) {
  return (
    <>
      {' '}
      <IconWithTooltip
        message={children}
        size="small"
        iconClassName={buildClassName(styles.advancedTooltip, isError && styles.advancedError)}
        tooltipClassName={styles.advancedTooltipContainer}
      />
    </>
  );
}
