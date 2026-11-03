import React, { memo, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Button from '../ui/Button';
import Transition from '../ui/Transition';
import AgentMenu from './AgentMenu';

import styles from './AgentHeader.module.scss';

interface OwnProps {
  isScrolled?: boolean;
  /** Shows the trailing "…" button of the chat menu, dimmed while the menu has no item */
  isMenuVisible?: boolean;
  /** The chat's name; without it the header says "Agent" */
  title?: string;
  /** The emoji the agent gave the chat */
  icon?: string;
  /** Shows the leading Back button, which goes back to the chat list */
  onBack?: NoneToVoidFunction;
  onReportProblem?: NoneToVoidFunction;
  onDelete?: NoneToVoidFunction;
}

function AgentHeader({
  isScrolled = false,
  isMenuVisible,
  title,
  icon,
  onBack,
  onReportProblem,
  onDelete,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();

  // A chat that has its menu has it from the start, as after the layout changes; a new chat's menu fades in
  const { ref: menuRef, shouldRender: shouldRenderMenu } = useShowTransition<HTMLDivElement>({
    isOpen: isMenuVisible,
    withShouldRender: true,
    noMountTransition: true,
  });
  // A screen with the button has it from the start; the chat list grows it as the user starts composing a chat
  const { ref: backButtonRef, shouldRender: shouldRenderBackButton } = useShowTransition<HTMLButtonElement>({
    isOpen: Boolean(onBack),
    withShouldRender: true,
    noMountTransition: true,
    className: false,
  });
  const renderedOnBack = useCurrentOrPrev(onBack, true);
  const getHeader = useLastCallback(() => ref.current);

  // A new name or emoji slides in, as when the agent names the chat after its first answer
  const titleSignature = `${icon ?? ''}\u0000${title ?? ''}`;
  const titleKeyRef = useRef({ signature: titleSignature, key: 0 });
  if (titleKeyRef.current.signature !== titleSignature) {
    titleKeyRef.current = { signature: titleSignature, key: titleKeyRef.current.key + 1 };
  }

  return (
    <div ref={ref} className={buildClassName(styles.header, isScrolled && 'is-scrolled')} data-agent-header>
      {shouldRenderBackButton ? (
        <Button
          ref={backButtonRef}
          isSimple
          isText
          kind="transparent"
          className={styles.backButton}
          onClick={renderedOnBack}
        >
          <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
      ) : <div />}
      <Transition
        name="slideVerticalFade"
        activeKey={titleKeyRef.current.key}
        className={styles.titleTransition}
        slideClassName={styles.titleSlide}
      >
        <span className={styles.headerTitle} role="heading" aria-level={1}>
          {icon && <span className={styles.titleIcon} aria-hidden>{icon}</span>}
          <span className={styles.titleText}>{title ?? lang('Agent')}</span>
        </span>
      </Transition>
      {shouldRenderMenu ? (
        <div ref={menuRef} className={styles.menuCell}>
          <AgentMenu
            className={styles.menuButton}
            menuClassName={styles.menu}
            getContainer={getHeader}
            onReportProblem={onReportProblem}
            onDelete={onDelete}
          />
        </div>
      ) : <div />}
    </div>
  );
}

export default memo(AgentHeader);
