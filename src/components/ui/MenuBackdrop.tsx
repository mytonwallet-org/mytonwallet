import React, { type ElementRef, memo, useLayoutEffect } from '../../lib/teact/teact';
import { toggleExtraClass } from '../../lib/teact/teact-dom';

import buildClassName from '../../util/buildClassName';

import useShowTransition from '../../hooks/useShowTransition';
import useToggleClass from '../../hooks/useToggleClass';

import styles from './MenuBackdrop.module.scss';

interface OwnProps {
  isMenuOpen?: boolean;
  contentRef: ElementRef<HTMLElement>;
  contentClassName?: string;
}

function MenuBackdrop({ isMenuOpen, contentRef, contentClassName }: OwnProps) {
  const {
    shouldRender: menuBackdropShouldRender,
    ref: menuBackdropRef,
  } = useShowTransition({
    isOpen: isMenuOpen,
    withShouldRender: true,
  });

  useLayoutEffect(() => {
    if (!contentRef.current) return;

    toggleExtraClass(contentRef.current, styles.wrapperVisible, menuBackdropShouldRender);
    toggleExtraClass(contentRef.current, styles.wrapperHide, menuBackdropShouldRender && !isMenuOpen);
    if (contentClassName) {
      toggleExtraClass(contentRef.current, contentClassName, menuBackdropShouldRender);
    }
  }, [contentClassName, contentRef, isMenuOpen, menuBackdropShouldRender]);

  useToggleClass({ className: 'with-menu-backdrop', isActive: isMenuOpen });
  // Some styles are applied only when menu is rendered, `.portraitContainer` is good example
  useToggleClass({ className: 'with-menu-backdrop-rendered', isActive: menuBackdropShouldRender });

  if (!menuBackdropShouldRender) return undefined;

  return (
    <div
      ref={menuBackdropRef}
      className={buildClassName(styles.backdrop, isMenuOpen && styles.visible)}
    />
  );
}

export default memo(MenuBackdrop);
