import React, { memo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import { DEFAULT_SLIPPAGE_VALUE } from '../../config';
import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
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
import Modal from '../ui/Modal';
import RichNumberInput from '../ui/RichNumberInput';

import styles from './TokenTradeSlippageModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  slippage: number;
  onClose: NoneToVoidFunction;
}

const SLIDER_STEPS = 1000;
/** A thumb dragged this close to a tick, in pixels, lands on the tick */
const TICK_SNAP_DISTANCE_PX = 8;

function TokenTradeSlippageModal({ isOpen, slippage, onClose }: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  return (
    <Modal
      isOpen={isOpen}
      isCompact={!isPortrait}
      noBackdrop={isPortrait}
      className={isPortrait ? styles.sheet : undefined}
      dialogClassName={styles.dialog}
      title={lang('Slippage')}
      hasCloseButton
      onClose={onClose}
    >
      <SlippageForm slippage={slippage} isSheet={isPortrait} onClose={onClose} />
    </Modal>
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
  const position = slippageToPosition(isValid ? value : DEFAULT_SLIPPAGE_VALUE);

  const handleInputChange = useLastCallback((stringValue?: string) => {
    setValue(stringValue ? Number(stringValue) : undefined);
  });

  // Nonsense becomes the default, and a value out of range becomes the nearest bound
  const handleInputBlur = useLastCallback(() => {
    setValue(value === undefined || Number.isNaN(value)
      ? DEFAULT_SLIPPAGE_VALUE
      : Math.min(MAX_SLIPPAGE_VALUE, Math.max(MIN_SLIPPAGE_VALUE, value)));
  });

  const handleSliderChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const slider = e.currentTarget;
    let nextPosition = Number(slider.value) / SLIDER_STEPS;

    const nearestTick = SLIPPAGE_TICKS.find((tick) => (
      Math.abs(slippageToPosition(tick) - nextPosition) * slider.offsetWidth < TICK_SNAP_DISTANCE_PX
    ));
    if (nearestTick !== undefined) {
      nextPosition = slippageToPosition(nearestTick);
    }

    setValue(positionToSlippage(nextPosition));
  });

  const handleDone = useLastCallback(() => {
    setSlippage({ slippage: value! });
    onClose();
  });

  return (
    <div className={buildClassName(styles.form, isSheet && styles.formSheet)}>
      <div className={styles.controls}>
        <button type="button" className={styles.boundButton} onClick={() => setValue(MIN_SLIPPAGE_VALUE)}>
          {lang('Min')}
        </button>
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
        <button type="button" className={styles.boundButton} onClick={() => setValue(MAX_SLIPPAGE_VALUE)}>
          {lang('Max')}
        </button>
      </div>

      <div className={styles.sliderArea} style={buildStyle(`--fill: ${position}`)}>
        <div className={styles.track} />
        <div className={styles.ticks} aria-hidden>
          {SLIPPAGE_TICKS.map((tick) => (
            <i
              key={tick}
              className={styles.tick}
              style={buildStyle(`--position: ${slippageToPosition(tick) * 100}%`)}
            />
          ))}
        </div>
        <input
          type="range"
          min="0"
          max={SLIDER_STEPS}
          step="1"
          value={Math.round(position * SLIDER_STEPS)}
          className={styles.slider}
          aria-label={lang('Slippage')}
          onChange={handleSliderChange}
        />
      </div>

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
