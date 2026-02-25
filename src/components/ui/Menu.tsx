import type { ElementRef, FC, TeactNode } from '../../lib/teact/teact';
import React, { beginHeavyAnimation, useEffect, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { stopEvent } from '../../util/domEvents';

import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useHistoryBack from '../../hooks/useHistoryBack';
import useMenuPosition, { type MenuPositionOptions } from '../../hooks/useMenuPosition';
import useShowTransition from '../../hooks/useShowTransition';
import useVirtualBackdrop from '../../hooks/useVirtualBackdrop';

import Portal from './Portal';

import styles from './Menu.module.scss';

export type { MenuPositionOptions } from '../../hooks/useMenuPosition';

type OwnProps = {
  children: TeactNode;
  menuRef?: ElementRef<HTMLDivElement>;
  isOpen: boolean;
  id?: string;
  className?: string;
  bubbleClassName?: string;
  type?: 'menu' | 'suggestion' | 'dropdown';
  role?: 'listbox';
  autoClose?: boolean;
  shouldSkipTransition?: boolean;
  noBackdrop?: boolean;
  withPortal?: boolean;
  noCloseOnBackdrop?: boolean;
  shouldCleanup?: boolean;
  onCloseAnimationEnd?: NoneToVoidFunction;
  onClose?: NoneToVoidFunction;
  onMouseEnter?: (e: React.MouseEvent<HTMLDivElement, MouseEvent>) => void;
  onMouseLeave?: (e: React.MouseEvent<HTMLDivElement, MouseEvent>) => void;
} & MenuPositionOptions;

export const ANIMATION_DURATION = 200;

const Menu: FC<OwnProps> = ({
  children,
  isOpen,
  id,
  menuRef,
  className,
  bubbleClassName,
  type = 'menu',
  role,
  autoClose = false,
  shouldSkipTransition,
  noBackdrop = false,
  withPortal,
  noCloseOnBackdrop = false,
  shouldCleanup,
  onCloseAnimationEnd,
  onClose,
  onMouseEnter,
  onMouseLeave,
  ...positionOptions
}) => {
  const containerRef = useRef<HTMLDivElement>();
  let bubbleRef = useRef<HTMLDivElement>();
  if (menuRef) {
    bubbleRef = menuRef;
  }

  useMenuPosition(isOpen, containerRef, bubbleRef, positionOptions);

  useHistoryBack({
    isActive: Boolean(isOpen && onClose),
    onBack: onClose!,
    shouldBeReplaced: true,
  });

  const {
    shouldRender,
  } = useShowTransition({
    isOpen,
    ref: bubbleRef,
    onCloseAnimationEnd,
    noMountTransition: shouldSkipTransition,
    noCloseTransition: shouldSkipTransition,
    withShouldRender: true,
  });

  useEffect(
    () => (isOpen && onClose ? captureEscKeyListener(onClose) : undefined),
    [isOpen, onClose],
  );

  useEffectWithPrevDeps(([prevIsOpen]) => {
    if (isOpen || (!isOpen && prevIsOpen === true)) {
      beginHeavyAnimation(ANIMATION_DURATION);
    }
  }, [isOpen]);

  useVirtualBackdrop(isOpen && !noBackdrop, containerRef, noCloseOnBackdrop ? undefined : onClose);

  const fullBubbleClassName = buildClassName(
    styles.bubble,
    bubbleClassName,
    'menu-bubble',
    styles[type],
  );

  if (shouldCleanup && !shouldRender) {
    return undefined;
  }

  const menu = (
    <div
      ref={containerRef}
      id={id}
      className={buildClassName(styles.wrapper, className, withPortal && styles.inPortal)}
      onMouseEnter={onMouseEnter}
      onMouseLeave={isOpen ? onMouseLeave : undefined}
    >
      {isOpen && !noBackdrop && (
        // This only prevents click events triggering on underlying elements
        <div className={styles.backdrop} onClick={stopEvent} />
      )}
      <div
        ref={bubbleRef}
        className={fullBubbleClassName}
        role={role}
        onClick={autoClose ? onClose : undefined}
      >
        {children}
      </div>
    </div>
  );

  if (withPortal) {
    return <Portal>{menu}</Portal>;
  }

  return menu;
};

export default Menu;
