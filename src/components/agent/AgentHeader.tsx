import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useShowTransition from '../../hooks/useShowTransition';

import AgentMenu from './AgentMenu';

import styles from './AgentHeader.module.scss';

interface OwnProps {
  isScrolled: boolean;
  isMenuVisible?: boolean;
  onClearChat: NoneToVoidFunction;
}

function AgentHeader({ isScrolled, isMenuVisible, onClearChat }: OwnProps) {
  const lang = useLang();

  const { ref: menuRef, shouldRender: shouldRenderMenu } = useShowTransition<HTMLDivElement>({
    isOpen: isMenuVisible,
    withShouldRender: true,
  });

  return (
    <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
      <div />
      <span className={styles.headerTitle}>{lang('Agent')}</span>
      {shouldRenderMenu ? (
        <div ref={menuRef}>
          <AgentMenu className={styles.menuButton} onClearChat={onClearChat} />
        </div>
      ) : <div />}
    </div>
  );
}

export default memo(AgentHeader);
