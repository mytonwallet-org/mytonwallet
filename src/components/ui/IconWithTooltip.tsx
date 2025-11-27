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
};

const ARROW_WIDTH = 0.6875 * REM;
const GAP = 2 * REM;

/** The component is designed to be positioned inline in text. Use a space symbol to create a gap on the left. */
const IconWithTooltip: FC<OwnProps> = ({
  message,
  emoji,
  size = 'medium',
  type = 'hint',
  direction = 'top',
  iconClassName,
  tooltipClassName,
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
          onMouseLeave={close}
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
        onMouseLeave={close}
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
            onClick={stopEvent}
            style={tooltipStyle.current}
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
