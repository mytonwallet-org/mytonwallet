import type { ChangeEvent } from 'react';
import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './Checkbox.module.scss';

type OwnProps = {
  id?: string;
  testId?: string;
  className?: string;
  contentClassName?: string;
  children?: TeactNode;
  checked: boolean;
  isDisabled?: boolean;
  onChange: (isChecked: boolean) => void;
};

function Checkbox({
  id,
  testId,
  className,
  contentClassName,
  children,
  checked,
  isDisabled,
  onChange,
}: OwnProps) {
  const handleChange = useLastCallback((e: ChangeEvent<HTMLInputElement>) => {
    e.preventDefault();
    onChange(e.currentTarget.checked);
  });

  return (
    <label className={buildClassName(styles.wrapper, className)} data-testid={testId}>
      <input
        id={id}
        type="checkbox"
        className={styles.input}
        checked={checked}
        disabled={isDisabled}
        tabIndex={0}
        onChange={!isDisabled ? handleChange : undefined}
      />
      <div className={buildClassName(styles.content, contentClassName)}>
        {children}
      </div>
    </label>
  );
}

export default memo(Checkbox);
