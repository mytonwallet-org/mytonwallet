import React, { type TeactNode, useEffect, useState } from '../../lib/teact/teact';

import type { SensitiveDataMaskSkin } from '../common/SensitiveDataMask';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { stopEvent } from '../../util/domEvents';
import getDeterministicRandom from '../../util/getDeterministicRandom';
import { vibrate } from '../../util/haptics';

import useShowTransition from '../../hooks/useShowTransition';
import useTimeout from '../../hooks/useTimeout';

import SensitiveDataMask from '../common/SensitiveDataMask';

import styles from './SensitiveData.module.scss';

// Matches iOS native app
const REVEAL_AUTO_HIDE_DELAY = 5000;

type ColsProps =
  | { cols: number; min?: never; max?: never; seed?: never }
  | { cols?: never; min: number; max: number; seed: string };

type OwnProps = ColsProps & {
  isActive?: boolean;
  rows: number;
  cellSize: number;
  align?: 'left' | 'center' | 'right';
  maskSkin?: SensitiveDataMaskSkin;
  shouldHoldSize?: boolean;
  className?: string;
  maskClassName?: string;
  contentClassName?: string;
  children: TeactNode;
};

function SensitiveData({
  isActive,
  rows,
  cols,
  min,
  max,
  seed,
  cellSize = 0,
  align = 'left',
  maskSkin,
  shouldHoldSize,
  className,
  maskClassName,
  contentClassName,
  children,
}: OwnProps) {
  const resolvedCols = cols ?? getDeterministicRandom(min, max, seed);
  const [isShown, setIsShown] = useState(false);

  const isMaskActive = isActive && !isShown;

  useEffect(() => {
    if (!isActive && isShown) {
      setIsShown(false);
    }
  }, [isActive, isShown]);

  useTimeout(
    () => setIsShown(false),
    isActive && isShown ? REVEAL_AUTO_HIDE_DELAY : undefined,
  );

  const {
    ref: contentRef,
  } = useShowTransition<HTMLDivElement>({
    isOpen: !isMaskActive,
    noMountTransition: !isMaskActive,
    className: 'slow',
  });

  const {
    shouldRender: shouldRenderSpoiler,
    ref: spoilerRef,
  } = useShowTransition<HTMLCanvasElement>({
    isOpen: isMaskActive,
    withShouldRender: true,
    className: 'slow',
  });

  function handleClick(e: React.UIEvent) {
    stopEvent(e);
    if (!isActive) return;

    setIsShown(!isShown);
    vibrate();
  }

  const fullClassName = buildClassName(
    styles.wrapper,
    className,
    isActive && styles.interactive,
    styles[align],
  );
  const spoilerClassName = buildClassName(
    styles.spoiler,
    maskClassName,
    styles[align],
  );
  const wrapperStyle = buildStyle(
    `--spoiler-width: calc(${cellSize * resolvedCols}px + var(--sensitive-data-extra-width, 0px))`,
    `min-height: ${cellSize * rows}px`,
    (isMaskActive || shouldHoldSize) && 'min-width: var(--spoiler-width);',
  );
  const contentFullClassName = buildClassName(
    styles.content,
    contentClassName,
    isMaskActive && styles.fixedWidth,
    isActive && styles.noninteractive,
  );

  return (
    <div
      style={wrapperStyle}
      className={fullClassName}
      onClick={isActive ? handleClick : undefined}
    >
      {shouldRenderSpoiler && (
        <SensitiveDataMask
          ref={spoilerRef}
          cols={resolvedCols}
          rows={rows}
          cellSize={cellSize}
          skin={maskSkin}
          className={spoilerClassName}
        />
      )}
      <div ref={contentRef} className={contentFullClassName}>
        {children}
      </div>
    </div>
  );
}

export default SensitiveData;
