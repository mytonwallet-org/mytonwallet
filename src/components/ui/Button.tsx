import type { ElementRef, TeactNode } from '../../lib/teact/teact';
import React, { memo, useState } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import LoadingDots from './LoadingDots';

import styles from './Button.module.scss';

export type OwnProps = {
  ref?: ElementRef<HTMLButtonElement>;
  children: TeactNode;
  id?: string;
  className?: string;
  style?: string;
  ariaLabel?: string;
  forFormId?: string;
  kind?: 'transparent';
  isSubmit?: boolean;
  isPrimary?: boolean;
  isSecondary?: boolean;
  isSmall?: boolean;
  isSimple?: boolean;
  isText?: boolean;
  isLoading?: boolean;
  isDisabled?: boolean;
  isRound?: boolean;
  isDestructive?: boolean;
  shouldStopPropagation?: boolean;
  onClick?: NoneToVoidFunction;
  onMouseDown?: (e: React.MouseEvent) => void;
  onMouseEnter?: (e: React.MouseEvent) => void;
  onContextMenu?: (e: React.MouseEvent) => void;
};

// Longest animation duration
const CLICKED_TIMEOUT = 400;

function Button({
  ref,
  children,
  id,
  className,
  style,
  ariaLabel,
  forFormId,
  kind,
  isSubmit,
  isPrimary,
  isSecondary,
  isSmall,
  isSimple,
  isText,
  isLoading,
  isDisabled,
  isRound,
  isDestructive,
  shouldStopPropagation,
  onClick,
  onMouseDown,
  onMouseEnter,
  onContextMenu,
}: OwnProps) {
  const [isClicked, setIsClicked] = useState(false);

  const handleClick = useLastCallback((event: React.MouseEvent) => {
    if (!isDisabled && onClick) {
      if (shouldStopPropagation) {
        event.stopPropagation();
      }
      onClick();
    }

    setIsClicked(true);
    setTimeout(() => {
      setIsClicked(false);
    }, CLICKED_TIMEOUT);
  });

  const loadingClassName = buildClassName(
    isLoading !== undefined && styles.loadingInit,
    isLoading && styles.loadingStart,
  );

  return (
    <button
      id={id}
      ref={ref}
      type={isSubmit || forFormId ? 'submit' : 'button'}
      className={buildClassName(
        styles.button,
        isPrimary && styles.primary,
        isSecondary && styles.secondary,
        isSmall && styles.sizeSmall,
        isSimple && styles.isSimple,
        isText && styles.isText,
        (isDisabled || isLoading) && styles.disabled,
        loadingClassName,
        isRound && styles.round,
        isDestructive && styles.destructive,
        isClicked && styles.clicked,
        className,
        kind && styles[kind],
      )}
      style={style}
      aria-label={ariaLabel}
      disabled={isDisabled || isLoading}
      form={forFormId}
      onClick={handleClick}
      onMouseDown={onMouseDown}
      onMouseEnter={onMouseEnter}
      onContextMenu={onContextMenu}
    >
      {children}
      <LoadingDots isActive={isLoading} className={styles.loadingDots} />
    </button>
  );
}

export default memo(Button);
