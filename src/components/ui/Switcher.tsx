import type { ChangeEvent } from 'react';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import styles from './Switcher.module.scss';

type OwnProps = {
  id?: string;
  name?: string;
  value?: string;
  label?: string;
  checked?: boolean;
  isDisabled?: boolean;
  className?: string;
  onChange?: (e: ChangeEvent<HTMLInputElement>) => void;
  onCheck?: (isChecked: boolean) => void;
  shouldStopPropagation?: boolean;
};

function Switcher({
  id,
  name,
  value,
  label,
  checked = false,
  isDisabled,
  className,
  onChange,
  onCheck,
  shouldStopPropagation,
}: OwnProps) {
  function handleChange(e: ChangeEvent<HTMLInputElement>) {
    onChange?.(e);
    onCheck?.(e.currentTarget.checked);
  }

  return (
    <label
      className={buildClassName(styles.container, isDisabled && styles.disabled, className)}
      title={label}
      aria-label={label}
      onClick={shouldStopPropagation ? (e) => e.stopPropagation() : undefined}
      tabIndex={0}
      role="button"
    >
      <input
        type="checkbox"
        id={id}
        name={name}
        value={value}
        checked={checked}
        disabled={isDisabled}
        className={styles.input}
        onChange={handleChange}
      />
      <span className={styles.widget} />
    </label>
  );
}

export default memo(Switcher);
