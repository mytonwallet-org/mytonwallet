import React, { memo } from '../../lib/teact/teact';

import useLang from '../../hooks/useLang';

import RichNumberInput from '../ui/RichNumberInput';

import styles from './TokenTrade.module.scss';

interface OwnProps {
  id: string;
  value?: string;
  prefix?: string;
  suffix?: string;
  decimals?: number;
  /** Shows a button that restores the amount the form started with, in place of the clear button */
  canReset?: boolean;
  /** Hides the clear button, which otherwise shows while the field has a value */
  noClear?: boolean;
  onChange: (value?: string) => void;
  onPressEnter: (e: React.FormEvent | React.UIEvent) => void;
  onClear: NoneToVoidFunction;
  onReset?: NoneToVoidFunction;
}

/** The amount field of a trade form together with its clear or reset button */
function TradeAmountInput({
  id, value, prefix, suffix, decimals, canReset, noClear, onChange, onPressEnter, onClear, onReset,
}: OwnProps) {
  const lang = useLang();

  function renderButton() {
    if (canReset) {
      return (
        <button
          type="button"
          className={styles.clearButton}
          aria-label={lang('Reset to Current Amount')}
          onClick={onReset}
        >
          <i className="icon-menu-reload" aria-hidden />
        </button>
      );
    }

    return !noClear && Boolean(value) && (
      <button type="button" className={styles.clearButton} aria-label={lang('Clear')} onClick={onClear}>
        <i className="icon-close-filled" aria-hidden />
      </button>
    );
  }

  return (
    <div className={styles.amountRow}>
      <RichNumberInput
        id={id}
        labelText={lang('Amount')}
        labelClassName="visually-hidden"
        value={value}
        prefix={prefix}
        suffix={suffix}
        decimals={decimals}
        className={styles.amountInput}
        inputClassName={styles.amountInputWrapper}
        valueClassName={styles.amountValue}
        onChange={onChange}
        onPressEnter={onPressEnter}
      />
      {renderButton()}
    </div>
  );
}

export default memo(TradeAmountInput);
