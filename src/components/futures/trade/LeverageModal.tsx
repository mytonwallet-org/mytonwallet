import React, { memo, useMemo, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsTradeState } from '../../../global/types';

import { hasPerpsAmount } from '../../../global/helpers/perps';
import buildClassName from '../../../util/buildClassName';
import { vibrate } from '../../../util/haptics';
import { toLatinDigits, toNativeDigits } from '../../../util/nativeDigits';
import {
  formatLeverage, formatPerpsMoney, formatPerpsMoneyEstimate, MISSING_VALUE,
} from '../helpers/formatPerps';
import { buildLeverageScale, leverageToPosition, positionToLeverage } from '../helpers/leverageScale';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../hooks/useDeviceScreen';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useTimeout from '../../../hooks/useTimeout';

import TradeSheetModal from '../../swap/TradeSheetModal';
import Button from '../../ui/Button';
import RangeSlider from '../../ui/RangeSlider';
import WarningMessage from '../../ui/WarningMessage';
import DetailRow from '../DetailRow';

import modalStyles from '../../ui/Modal.module.scss';
import futuresStyles from '../Futures.module.scss';
import styles from './LeverageModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  trade: PerpsTradeState;
  asset: ApiPerpsMarketAsset;
  onClose: NoneToVoidFunction;
}

const MIN_LEVERAGE = 1;
const ESTIMATE_DEBOUNCE_MS = 250;

/** The leverage of a new position */
function LeverageModal({
  isOpen, trade, asset, onClose,
}: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  return (
    <TradeSheetModal isOpen={isOpen} title={lang('Leverage')} onClose={onClose}>
      <LeverageForm trade={trade} asset={asset} isSheet={isPortrait} onClose={onClose} />
    </TradeSheetModal>
  );
}

export default memo(LeverageModal);

interface LeverageFormProps extends Omit<OwnProps, 'isOpen'> {
  isSheet: boolean;
}

// Lives in its own component so that the draft value resets every time the modal opens, which unmounts the content
const LeverageForm = memo(({
  trade, asset, isSheet, onClose,
}: LeverageFormProps) => {
  const { setPerpsTradeLeverage, loadPerpsLeverageEstimate } = getActions();
  const lang = useLang();

  const [value, setValue] = useState(trade.leverage);
  // The text of the field while the user types the leverage, which may be empty for a moment
  const [typedText, setTypedText] = useState<string>();
  const { symbol, context: { markPx: markPrice } } = asset;
  // The SDK refuses a leverage above the market maximum. A position above it keeps its leverage only while unchanged.
  const maxLeverage = Math.max(asset.maxLeverage, MIN_LEVERAGE);
  const scale = useMemo(() => buildLeverageScale(MIN_LEVERAGE, maxLeverage), [maxLeverage]);
  const hasAmount = hasPerpsAmount(trade.amount);
  // The quote of the form already estimates its own leverage
  const { preview } = trade;
  const isPreviewLeverage = preview !== undefined && value === preview.leverage && preview.kind !== 'unchanged';
  const estimate = trade.leverageEstimates?.[value] ?? (isPreviewLeverage
    ? { liquidationPrice: preview.estimatedLiquidationPrice }
    : undefined);
  // The slider gives only valid values, while the field may hold an empty or an out-of-range one for a moment
  const typedTextLeverage = Number(typedText);
  const isValueValid = typedText === undefined
    || (typedTextLeverage >= MIN_LEVERAGE && typedTextLeverage <= maxLeverage);
  const hasEstimate = Boolean(estimate);

  const shouldLoadEstimate = hasAmount && !hasEstimate;

  useTimeout(() => {
    loadPerpsLeverageEstimate({ leverage: value });
  }, shouldLoadEstimate ? ESTIMATE_DEBOUNCE_MS : undefined, [value]);

  const handleSliderChange = useLastCallback((position: number) => {
    const nextValue = positionToLeverage(scale, position);
    // Each step of the leverage gives a tick, as in the native apps
    if (nextValue !== value) vibrate();

    setTypedText(undefined);
    setValue(nextValue);
  });

  const handleMinClick = useLastCallback(() => {
    setTypedText(undefined);
    setValue(MIN_LEVERAGE);
  });

  const handleMaxClick = useLastCallback(() => {
    setTypedText(undefined);
    setValue(maxLeverage);
  });

  // A value out of the range stays in the field, and Done waits for a valid one, as on iOS
  const handleInputChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const digits = toLatinDigits(e.currentTarget.value).replace(/\D/g, '');
    const typedLeverage = Number(digits);

    setTypedText(digits);
    if (typedLeverage >= MIN_LEVERAGE && typedLeverage <= maxLeverage) setValue(typedLeverage);
  });

  const handleInputBlur = useLastCallback(() => {
    if (isValueValid) setTypedText(undefined);
  });

  const handleDone = useLastCallback(() => {
    if (!isValueValid) return;

    setPerpsTradeLeverage({ leverage: value });
    onClose();
  });

  // While the estimate of a new value loads, the last price stays on screen dimmed, as on iOS
  const isEstimateLoading = shouldLoadEstimate && isValueValid;
  const lastLiquidationPrice = useCurrentOrPrev(estimate?.liquidationPrice, true);
  const liquidationPrice = isEstimateLoading ? lastLiquidationPrice : estimate?.liquidationPrice;
  const liquidationText = isValueValid ? formatPerpsMoneyEstimate(liquidationPrice) : MISSING_VALUE;
  const fieldText = typedText ?? String(value);

  return (
    <div className={buildClassName(styles.form, isSheet && styles.formSheet)}>
      <div className={styles.controls}>
        <RangeSlider
          position={leverageToPosition(scale, value)}
          tickPositions={scale.positions}
          ariaLabel={lang('Leverage')}
          ariaValueText={formatLeverage(value)}
          onChange={handleSliderChange}
          onMinClick={handleMinClick}
          onMaxClick={handleMaxClick}
        >
          <label className={styles.value}>
            <input
              className={styles.valueInput}
              style={`width: ${Math.max(fieldText.length, 1)}ch`}
              value={toNativeDigits(fieldText)}
              inputMode="numeric"
              aria-label={lang('Leverage')}
              onChange={handleInputChange}
              onBlur={handleInputBlur}
            />
            <span className={styles.valueSuffix}>x</span>
          </label>
        </RangeSlider>
      </div>

      <div className={styles.prices}>
        <DetailRow
          label={lang('$perps_asset_price', { asset: symbol })}
          value={formatPerpsMoney(markPrice)}
          className={styles.priceRow}
          labelClassName={styles.priceLabel}
        />
        <DetailRow
          label={lang('Liquidation Price')}
          value={liquidationText}
          className={styles.priceRow}
          labelClassName={styles.priceLabel}
          valueClassName={buildClassName(futuresStyles.dimmable, isEstimateLoading && futuresStyles.stale)}
        />
      </div>

      <div className={styles.footer}>
        <WarningMessage>{lang('$perps_leverage_disclaimer')}</WarningMessage>
        <Button
          isPrimary
          isDisabled={!isValueValid}
          className={buildClassName(modalStyles.buttonFullWidth, styles.doneButton, isSheet && styles.doneButtonSheet)}
          onClick={handleDone}
        >
          {lang('Done')}
        </Button>
      </div>
    </div>
  );
});
