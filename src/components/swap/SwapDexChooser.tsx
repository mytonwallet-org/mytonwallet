import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiSwapDexLabel, ApiSwapEstimateVariant } from '../../api/types';
import type { GlobalState, UserSwapToken } from '../../global/types';
import { SwapInputSource } from '../../global/types';

import {
  DEFAULT_OUR_SWAP_FEE,
  SHORT_FRACTION_DIGITS,
  SWAP_DEX_LABELS,
  WHOLE_PART_DELIMITER,
} from '../../config';
import { getNumberParts } from '../../global/helpers/number';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { fromDecimal, toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import getSwapRate from '../../util/swap/getSwapRate';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Button from '../ui/Button';
import Modal from '../ui/Modal';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './SwapDexChooser.module.scss';

import DedustPath from '../../assets/logo/dedust.png';
import StonfiPath from '../../assets/logo/stonfi.png';

interface OwnProps {
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
  isStatic?: boolean;
}

interface StateProps {
  currentSwap: GlobalState['currentSwap'];
  swapVersion: GlobalState['swapVersion'];
}

const IS_WHOLE_PART_BIG_REGEX = /^\d{5,}([.,]|$)/;

function SwapDexChooser({
  tokenIn,
  tokenOut,
  isStatic,
  currentSwap: {
    amountOut,
    amountIn,
    estimates,
    currentDexLabel,
    bestRateDexLabel,
    inputSource,
    ourFeePercent = DEFAULT_OUR_SWAP_FEE,
  },
  swapVersion,
}: OwnProps & StateProps) {
  const { setSwapDex } = getActions();

  const lang = useLang();

  const [isModalOpen, openModal, closeModal] = useFlag(false);
  const [selectedDexLabel, setSelectedDexLabel] = useState<ApiSwapDexLabel | undefined>(currentDexLabel);
  const renderedDexItems = useCurrentOrPrev(estimates?.length ? estimates : undefined, true);
  const renderedCurrentDexLabel = useCurrentOrPrev(currentDexLabel, true);
  const renderedBestRateDexLabel = useCurrentOrPrev(bestRateDexLabel, true);
  const isBestRateSelected = Boolean(bestRateDexLabel && bestRateDexLabel === selectedDexLabel);
  const confirmLabel = isBestRateSelected
    ? lang('Use Best Rate')
    : lang('Switch to %dex_name%', {
      dex_name: selectedDexLabel ? SWAP_DEX_LABELS[selectedDexLabel] : '',
    });

  const shouldRenderForSwapV2 = !!estimates?.length && !!tokenOut && !!amountOut && !!amountIn;

  const { shouldRender, ref: rootRef } = useShowTransition({
    isOpen: swapVersion === 2 && shouldRenderForSwapV2,
    withShouldRender: true,
  });

  const handleDexConfirm = useLastCallback(() => {
    if (selectedDexLabel) {
      setSwapDex({ dexLabel: selectedDexLabel });
    }
    closeModal();
  });

  function toggleDexMenu() {
    if (isModalOpen) {
      closeModal();
    } else {
      setSelectedDexLabel(currentDexLabel);
      openModal();
    }
  }

  const { shouldRender: shouldRenderBenefit, value: benefitAmount } = useMemo(() => {
    return calculateBenefitAmount({
      ourFeePercent,
      decimals: inputSource === SwapInputSource.In ? tokenOut?.decimals : tokenIn?.decimals,
      estimates,
      inputSource,
      bestRateDexLabel: renderedBestRateDexLabel,
    });
  }, [renderedBestRateDexLabel, estimates, inputSource, ourFeePercent, tokenIn?.decimals, tokenOut?.decimals]);

  const renderedAmounts = useMemo<Record<ApiSwapDexLabel, TeactNode> | undefined>(() => {
    if (!renderedDexItems?.length || renderedDexItems.length < 2) return undefined;

    return renderedDexItems.reduce((acc, item) => {
      const { fromAmount, toAmount, dexLabel } = item;
      const amount = inputSource === SwapInputSource.In ? toAmount : fromAmount;
      const token = inputSource === SwapInputSource.In ? tokenOut! : tokenIn!;

      if (IS_WHOLE_PART_BIG_REGEX.test(amount)) {
        const formattedAmount = formatDexItemAmount(amount, token);

        if (formattedAmount) {
          acc[dexLabel] = formattedAmount;
        }
      } else {
        acc[dexLabel] = formatCurrency(amount, token.symbol);
      }

      return acc;
    }, {} as Record<ApiSwapDexLabel, TeactNode>);
  }, [inputSource, renderedDexItems, tokenIn, tokenOut]);

  if (!shouldRender || !renderedDexItems?.length) return undefined;

  const buttonContent = (
    <>
      {renderedBestRateDexLabel === renderedCurrentDexLabel && renderedDexItems.length > 1 && (
        <span className={styles.label}><span className={styles.labelText}>{lang('Best Rate')}</span></span>
      )}
      {lang('via %dex_name%', {
        dex_name: <strong>{SWAP_DEX_LABELS[renderedCurrentDexLabel!]}</strong>,
      })}
      {renderedDexItems.length > 1 && (
        <i className={buildClassName('icon-chevron-right', styles.iconArrowRight)} aria-hidden />
      )}
    </>
  );

  if (renderedDexItems.length === 1) {
    return (
      <div ref={rootRef} className={styles.root}>
        <div className={styles.container}>
          <span className={buildClassName(styles.content, isStatic && styles.static)}>{buttonContent}</span>
        </div>
      </div>
    );
  }

  function renderedDexItem(item: ApiSwapEstimateVariant) {
    const rate = getSwapRate(item.fromAmount, item.toAmount, tokenIn, tokenOut);

    return (
      <div
        key={item.dexLabel}
        tabIndex={0}
        role="button"
        className={buildClassName(
          styles.dexItem,
          renderedBestRateDexLabel === item.dexLabel && styles.bestRate,
          selectedDexLabel === item.dexLabel && styles.current,
        )}
        onClick={() => { setSelectedDexLabel(item.dexLabel); }}
      >
        <div className={styles.dexTitle}>
          <img
            src={item.dexLabel === 'dedust' ? DedustPath : StonfiPath}
            alt={SWAP_DEX_LABELS[item.dexLabel]}
            className={styles.dexIcon}
          />
          {SWAP_DEX_LABELS[item.dexLabel]}
        </div>
        <div className={styles.dexValue}>{renderedAmounts?.[item.dexLabel]}</div>
        <div className={styles.dexExchangeRate}>
          {rate ? <>{rate.firstCurrencySymbol}&nbsp;≈ {rate.price}&nbsp;{rate.secondCurrencySymbol}</> : undefined}
        </div>
        {item.dexLabel === renderedBestRateDexLabel && (
          <span className={styles.bestLabel}>{lang('Best')}</span>
        )}
      </div>
    );
  }

  function renderBenefitAmount() {
    if (inputSource === SwapInputSource.Out) {
      return (
        <p className={buildClassName(styles.dexInfo, !isBestRateSelected && styles.dexInfoDisabled)}>
          {renderText(lang('You will spend %amount% **less**.', {
            amount: <strong>{formatCurrency(benefitAmount, tokenIn!.symbol)}</strong>,
          }))}
        </p>
      );
    }

    return (
      <p className={buildClassName(styles.dexInfo, !isBestRateSelected && styles.dexInfoDisabled)}>
        {renderText(lang('You will receive %amount% **more**.', {
          amount: <strong>{formatCurrency(benefitAmount, tokenOut!.symbol)}</strong>,
        }))}
      </p>
    );
  }

  return (
    <div ref={rootRef} className={styles.root}>
      <div className={styles.container}>
        <button
          type="button"
          className={buildClassName(styles.button, isStatic && styles.static)}
          onClick={toggleDexMenu}
        >
          {buttonContent}
        </button>
        <Modal
          isOpen={isModalOpen}
          isCompact
          title={lang('Built-in DEX Aggregator')}
          onClose={closeModal}
        >
          <div className={styles.dexList}>
            {renderedDexItems.map((item) => renderedDexItem(item))}
          </div>

          <p className={buildClassName(styles.dexInfo, !isBestRateSelected && styles.dexInfoDisabled)}>
            {renderText(lang('$swap_dex_chooser_rate_title'))}
          </p>
          {shouldRenderBenefit && renderBenefitAmount()}

          <div className={buildClassName(modalStyles.buttons, styles.dexSubmitButtons)}>
            <Transition
              activeKey={isBestRateSelected ? 0 : 1}
              name="semiFade"
              slideClassName={styles.dexSubmitSlide}
            >
              <Button
                isPrimary
                className={buildClassName(modalStyles.buttonFullWidth, isBestRateSelected && styles.dexBestRateButton)}
                onClick={handleDexConfirm}
              >
                {confirmLabel}
              </Button>
            </Transition>

          </div>
        </Modal>
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    currentSwap: global.currentSwap,
    swapVersion: global.swapVersion,
  };
})(SwapDexChooser));

function calculateBenefitAmount({
  ourFeePercent,
  decimals,
  bestRateDexLabel,
  estimates,
  inputSource,
}: {
  ourFeePercent: number;
  decimals?: number;
  estimates?: ApiSwapEstimateVariant[];
  bestRateDexLabel?: ApiSwapDexLabel;
  inputSource?: SwapInputSource;
}) {
  if (!estimates || estimates.length < 2) {
    return { shouldRender: false, value: '0' };
  }

  const bestRateEstimate = estimates.find(({ dexLabel }) => dexLabel === bestRateDexLabel);
  const otherEstimate = estimates.find(({ dexLabel }) => dexLabel !== bestRateDexLabel);

  if (!otherEstimate || !bestRateEstimate) {
    return { shouldRender: false, value: '0' };
  }

  const isDirectSwap = inputSource === SwapInputSource.In;
  const amountKey = isDirectSwap ? 'toAmount' : 'fromAmount';
  const ourFeeValue = (Number(bestRateEstimate[amountKey]) / 100) * ourFeePercent;
  const benefit = (fromDecimal(bestRateEstimate[amountKey], decimals) - fromDecimal(otherEstimate[amountKey], decimals))
    * (isDirectSwap ? 1n : -1n);
  const shouldRender = (benefit - fromDecimal(ourFeeValue, decimals)) > 0n;

  return {
    shouldRender,
    value: toDecimal(benefit, decimals),
  };
}

function formatDexItemAmount(toAmount: string, tokenOut: UserSwapToken): TeactNode | undefined {
  const parts = getNumberParts(toAmount, SHORT_FRACTION_DIGITS);
  if (!parts) return undefined;

  const [, wholePartRaw, dotPart, fractionPart] = parts;
  const fractionStr = fractionPart || dotPart
    ? `.${(fractionPart || '').substring(0, SHORT_FRACTION_DIGITS)}`
    : '';

  const formattedWholePart = wholePartRaw.replace(/\d(?=(\d{3})+($))/g, `$&${WHOLE_PART_DELIMITER}`);

  return (
    <>
      {formattedWholePart}
      <span className={styles.dexValueFractional}>{fractionStr}&thinsp;{tokenOut.symbol}</span>
    </>
  );
}
