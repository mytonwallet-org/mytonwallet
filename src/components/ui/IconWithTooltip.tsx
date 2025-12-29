import type { FC, TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useRef,
} from '../../lib/teact/teact';

import type { EmojiIcon } from './Emoji';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { IS_TOUCH_ENV, REM } from '../../util/windowEnvironment';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useUniqueId from '../../hooks/useUniqueId';

import Emoji from './Emoji';
import Portal from './Portal';

import styles from './IconWithTooltip.module.scss';

type OwnProps = {
  message: TeactNode;
  emoji?: EmojiIcon;
  size?: 'small' | 'medium';
  type?: 'hint' | 'warning';
  direction?: 'top' | 'bottom';
  iconClassName?: string;
  tooltipClassName?: string;
  canHoverOnTooltip?: boolean;
};

const ARROW_WIDTH = 0.6875 * REM;
const GAP = 2 * REM;
const CLOSE_TIMER_DELAY = 150;

/** The component is designed to be positioned inline in text. Use a space symbol to create a gap on the left. */
const IconWithTooltip: FC<OwnProps> = ({
  message,
  emoji,
  size = 'medium',
  type = 'hint',
  direction = 'top',
  iconClassName,
  tooltipClassName,
  canHoverOnTooltip = false,
}) => {
  const [isOpen, open, close] = useFlag();
  const { shouldRender, ref: tooltipContainerRef } = useShowTransition({
    isOpen,
    withShouldRender: true,
  });
  const colorClassName = type === 'warning' && styles[`color-${type}`];

  const iconRef = useRef<HTMLDivElement>();
  const tooltipRef = useRef<HTMLDivElement>();

  const tooltipStyle = useRef<string>();
  const arrowStyle = useRef<string>();

  const closeTimerRef = useRef<number | undefined>();

  const randomTooltipKey = useUniqueId();

  const handleClickOutside = useLastCallback((event: Event) => {
    if (!(event.target as HTMLElement).closest(`[data-tooltip-key="${randomTooltipKey}"]`)) {
      close();
    }
  });

  useEffect(() => {
    if (!isOpen) return undefined;
    document.addEventListener('touchstart', handleClickOutside);

    return () => {
      document.removeEventListener('touchstart', handleClickOutside);
    };
  }, [isOpen, close, handleClickOutside]);

  useEffect(() => {
    if (!iconRef.current || !tooltipRef.current) return;

    const {
      top, left, width, height: iconHeight,
    } = iconRef.current.getBoundingClientRect();
    const {
      width: tooltipWidth,
      height: tooltipHeight,
    } = tooltipRef.current.getBoundingClientRect();

    const tooltipCenter = (window.innerWidth - tooltipWidth) / 2;
    const arrowPosition = left - tooltipCenter + width / 2 - ARROW_WIDTH / 2;
    const horizontalOffset = arrowPosition < GAP ? GAP - arrowPosition : 0;

    const isTop = direction === 'top';
    const tooltipTop = isTop
      ? top - tooltipHeight - ARROW_WIDTH
      : top + iconHeight + ARROW_WIDTH;
    const arrowTop = isTop
      ? tooltipHeight - ARROW_WIDTH / 2 - 1
      : -ARROW_WIDTH / 2 + 1;

    const tooltipVerticalStyle = `top: ${tooltipTop}px;`;
    const tooltipHorizontalStyle = `left: ${tooltipCenter - horizontalOffset}px;`;
    const arrowHorizontalStyle = `left: ${arrowPosition + horizontalOffset}px;`;
    const arrowVerticalStyle = `top: ${arrowTop}px;`;

    tooltipStyle.current = `${tooltipVerticalStyle} ${tooltipHorizontalStyle}`;
    arrowStyle.current = `${arrowVerticalStyle} ${arrowHorizontalStyle}`;
  }, [shouldRender, direction]);

  function startCloseTimer() {
    closeTimerRef.current = window.setTimeout(() => close(), CLOSE_TIMER_DELAY);
  }

  function clearCloseTimer() {
    if (closeTimerRef.current) {
      window.clearTimeout(closeTimerRef.current);
      closeTimerRef.current = undefined;
    }
  }

  useEffect(() => {
    return clearCloseTimer;
  }, [isOpen]);

  const handleTooltipClick = useLastCallback((e: React.MouseEvent) => {
    // Allow click events on links
    const target = e.target as HTMLElement;
    if (target.tagName === 'A' || target.closest('a')) return;
    stopEvent(e);
  });

  function renderIcon() {
    const commonClassName = buildClassName(styles.icon, iconClassName, styles[size], colorClassName);
    const onClick = IS_TOUCH_ENV ? stopEvent : undefined;

    if (emoji) {
      return (
        <span
          ref={iconRef}
          className={commonClassName}
          data-tooltip-key={randomTooltipKey}
          onClick={onClick}
          onMouseEnter={open}
          onMouseLeave={canHoverOnTooltip ? startCloseTimer : close}
        >
          <Emoji from={emoji} />
        </span>
      );
    }

    return (
      <i
        ref={iconRef}
        className={buildClassName(
          commonClassName,
          styles.fontIcon,
          type === 'warning' ? 'icon-exclamation' : 'icon-question',
        )}
        data-tooltip-key={randomTooltipKey}
        onClick={onClick}
        onMouseEnter={open}
        onMouseLeave={canHoverOnTooltip ? startCloseTimer : close}
      />
    );
  }

  return (
    <>
      {shouldRender && (
        <Portal>
          <div
            ref={tooltipContainerRef}
            className={buildClassName(styles.container, styles[direction])}
            style={tooltipStyle.current}
            onMouseEnter={canHoverOnTooltip ? clearCloseTimer : undefined}
            onMouseLeave={canHoverOnTooltip ? startCloseTimer : close}
            onClick={handleTooltipClick}
          >
            <div
              ref={tooltipRef}
              className={buildClassName(styles.tooltip, styles[size], colorClassName, tooltipClassName)}
            >
              {message}
            </div>
            <div className={styles.arrow} style={arrowStyle.current} />
          </div>
        </Portal>
      )}
      {renderIcon()}
    </>
  );
};

export default memo(IconWithTooltip);
