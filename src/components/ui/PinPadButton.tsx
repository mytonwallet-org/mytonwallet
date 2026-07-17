import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useState } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';

import styles from './PinPad.module.scss';

interface OwnProps {
  value?: any;
  children?: TeactNode;
  className?: string;
  isDisabled?: boolean;
  onClick?: (value?: any) => void;
}

const CLICKED_TIMEOUT_MS = 200;

function PinPadButton({
  value, children, className, isDisabled, onClick,
}: OwnProps) {
  const [isClicked, setIsClicked] = useState(false);

  const handleClick = () => {
    vibrate();
    onClick?.(value);
    setIsClicked(true);
    setTimeout(() => {
      setIsClicked(false);
    }, CLICKED_TIMEOUT_MS);
  };
  return (
    <div
      onMouseDown={!isDisabled ? handleClick : undefined}
      className={buildClassName(styles.button, isClicked && styles.buttonActive, className)}
      role="button"
      tabIndex={0}
    >
      {value || children}
    </div>
  );
}

export default memo(PinPadButton);
