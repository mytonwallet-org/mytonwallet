import React, { memo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { DEFAULT_SLIPPAGE_VALUE } from '../../config';
import buildClassName from '../../util/buildClassName';
import {
  isSlippageValid,
  MAX_SLIPPAGE_VALUE,
  MIN_SLIPPAGE_VALUE,
  positionToSlippage,
  SLIPPAGE_TICKS,
  slippageToPosition,
} from '../../util/swap/slippage';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import RangeSlider from '../ui/RangeSlider';
import RichNumberInput from '../ui/RichNumberInput';
import TradeSheetModal from './TradeSheetModal';

import styles from './TokenTradeSlippageModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  slippage: number;
  onClose: NoneToVoidFunction;
}

const TICK_POSITIONS = SLIPPAGE_TICKS.map(slippageToPosition);

function TokenTradeSlippageModal({ isOpen, slippage, onClose }: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  return (
    <TradeSheetModal isOpen={isOpen} title={lang('Slippage')} onClose={onClose}>
      <SlippageForm slippage={slippage} isSheet={isPortrait} onClose={onClose} />
    </TradeSheetModal>
  );
}

export default memo(TokenTradeSlippageModal);

interface SlippageFormProps extends Pick<OwnProps, 'slippage' | 'onClose'> {
  isSheet: boolean;
}

// Lives in its own component so that the draft value resets every time the modal opens, which unmounts the content
const SlippageForm = memo(({ slippage, isSheet, onClose }: SlippageFormProps) => {
  const { setSlippage } = getActions();
  const lang = useLang();

  const [value, setValue] = useState<number | undefined>(slippage);
  const isValid = isSlippageValid(value);
  const sliderValue = isValid ? value : DEFAULT_SLIPPAGE_VALUE;
  const position = slippageToPosition(sliderValue);

  const handleInputChange = useLastCallback((stringValue?: string) => {
    setValue(stringValue ? Number(stringValue) : undefined);
  });

  // Nonsense becomes the default, and a value out of range becomes the nearest bound
  const handleInputBlur = useLastCallback(() => {
    setValue(value === undefined || Number.isNaN(value)
      ? DEFAULT_SLIPPAGE_VALUE
      : Math.min(MAX_SLIPPAGE_VALUE, Math.max(MIN_SLIPPAGE_VALUE, value)));
  });

  const handleSliderChange = useLastCallback((nextPosition: number) => {
    setValue(positionToSlippage(nextPosition));
  });

  const handleMinClick = useLastCallback(() => {
    setValue(MIN_SLIPPAGE_VALUE);
  });

  const handleMaxClick = useLastCallback(() => {
    setValue(MAX_SLIPPAGE_VALUE);
  });

  const handleDone = useLastCallback(() => {
    setSlippage({ slippage: value! });
    onClose();
  });

  return (
    <div className={buildClassName(styles.form, isSheet && styles.formSheet)}>
      <RangeSlider
        position={position}
        tickPositions={TICK_POSITIONS}
        ariaLabel={lang('Slippage')}
        ariaValueText={`${sliderValue}%`}
        onChange={handleSliderChange}
        onMinClick={handleMinClick}
        onMaxClick={handleMaxClick}
      >
        <RichNumberInput
          value={value?.toString()}
          suffix="%"
          decimals={1}
          size="normal"
          hasError={!isValid}
          className={styles.valueCard}
          inputClassName={styles.valueInputWrapper}
          valueClassName={styles.valueInput}
          onChange={handleInputChange}
          onBlur={handleInputBlur}
        />
      </RangeSlider>

      <Button
        isPrimary
        isDisabled={!isValid}
        className={buildClassName(styles.doneButton, isSheet && styles.doneButtonSheet)}
        onClick={handleDone}
      >
        {lang('Done')}
      </Button>
    </div>
  );
});
