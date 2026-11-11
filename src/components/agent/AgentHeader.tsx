import React, { memo, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import AgentSupportIcon from '../agentV2/AgentSupportIcon';
import Button from '../ui/Button';
import Transition from '../ui/Transition';
import AgentMenu from './AgentMenu';

import styles from './AgentHeader.module.scss';

interface OwnProps {
  isScrolled?: boolean;
  /** Shows the trailing "…" button of the chat menu once the menu has an item */
  isMenuVisible?: boolean;
  /** The chat's name; without it the header says "Agent" */
  title?: string;
  /** The emoji the agent gave the chat */
  icon?: string;
  /** The line under the name that tells that support has the chat, with its headset */
  subtitle?: string;
  /** Shows the leading Back button, which goes back to the chat list */
  onBack?: NoneToVoidFunction;
  onReportProblem?: NoneToVoidFunction;
  onDelete?: NoneToVoidFunction;
  /** Shows the trailing bell in place of the chat menu, as in the news feed; it opens the daily digest's settings */
  onOpenDigestSettings?: NoneToVoidFunction;
}

function AgentHeader({
  isScrolled = false,
  isMenuVisible,
  title,
  icon,
  subtitle,
  onBack,
  onReportProblem,
  onDelete,
  onOpenDigestSettings,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();

  // A chat that has its menu has it from the start, as after the layout changes; a new chat's menu fades in, as does a
  // menu that gets its first item. A menu without items shows no button. The bell takes the menu's place.
  const { ref: menuRef, shouldRender: shouldRenderMenu } = useShowTransition<HTMLDivElement>({
    isOpen: Boolean(onOpenDigestSettings) || (isMenuVisible && Boolean(onReportProblem || onDelete)),
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
  const titleSignature = `${icon ?? ''}\u0000${title ?? ''}\u0000${subtitle ?? ''}`;
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
        <span className={buildClassName(styles.headerTitle, subtitle && styles.headerTitleWithSubtitle)}>
          <span className={styles.titleLine} role="heading" aria-level={1}>
            {icon && <span className={styles.titleIcon} aria-hidden>{icon}</span>}
            <span className={styles.titleText}>{title ?? lang('Agent')}</span>
          </span>
          {subtitle && (
            <span className={styles.subtitle}>
              <AgentSupportIcon className={styles.subtitleIcon} />
              <span className={styles.subtitleText}>{subtitle}</span>
            </span>
          )}
        </span>
      </Transition>
      {shouldRenderMenu ? (
        <div ref={menuRef} className={styles.menuCell}>
          {onOpenDigestSettings ? (
            <Button
              isSimple
              isText
              kind="transparent"
              className={styles.menuButton}
              ariaLabel={lang('$agent_digest_sheet_title')}
              onClick={onOpenDigestSettings}
            >
              <svg className={styles.bellIcon} viewBox="0 0 24 24" aria-hidden>
                <path d="M6 8.5a6 6 0 0 1 12 0c0 6 2.5 8 2.5 8h-17S6 14.5 6 8.5Z" />
                <path d="M10.1 20a2.2 2.2 0 0 0 3.8 0" />
              </svg>
            </Button>
          ) : (
            <AgentMenu
              className={styles.menuButton}
              menuClassName={styles.menu}
              getContainer={getHeader}
              onReportProblem={onReportProblem}
              onDelete={onDelete}
            />
          )}
        </div>
      ) : <div />}
    </div>
  );
}

export default memo(AgentHeader);
