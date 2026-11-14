import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useRef } from '../../lib/teact/teact';

import type { AgentV2SupportRequestSource } from '../../api/agentV2/types';

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
  /** A panel is attached under the header, which draws on the backdrop the two share */
  hasAccessory?: boolean;
  /** Shows the trailing "…" button of the chat menu once the menu has an item */
  isMenuVisible?: boolean;
  /** The chat's name; without it the header says "Agent" */
  title?: string;
  /** Stands in the title's place, as the news feed's view switch */
  titleContent?: TeactNode;
  /** The emoji the agent gave the chat */
  icon?: string;
  /** The line under the name that tells that support has the chat, with its headset */
  subtitle?: string;
  /** Shows the leading Back button, which goes back to the chat list */
  onBack?: NoneToVoidFunction;
  onReportProblem?: NoneToVoidFunction;
  /** Shows the support button before the "…" button, enabled by `canRequestSupport` */
  onRequestSupport?: (source: AgentV2SupportRequestSource) => void;
  canRequestSupport?: boolean;
  onDelete?: NoneToVoidFunction;
  /** Shows the settings button in place of the chat menu, as in the news feed; it opens the daily digest's settings */
  onOpenDigestSettings?: NoneToVoidFunction;
}

function AgentHeader({
  isScrolled = false,
  hasAccessory = false,
  isMenuVisible,
  title,
  titleContent,
  icon,
  subtitle,
  onBack,
  onReportProblem,
  onRequestSupport,
  canRequestSupport = false,
  onDelete,
  onOpenDigestSettings,
}: OwnProps) {
  const lang = useLang();
  const ref = useRef<HTMLDivElement>();

  // A chat that has its menu has it from the start, as after the layout changes; a new chat's menu fades in, as does a
  // menu that gets its first item. A menu without items shows no button. The settings button takes the menu's place.
  const { ref: menuRef, shouldRender: shouldRenderMenu } = useShowTransition<HTMLDivElement>({
    isOpen: Boolean(onOpenDigestSettings)
      || (isMenuVisible && Boolean(onReportProblem || onRequestSupport || onDelete)),
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
  const handleRequestSupport = useLastCallback(() => onRequestSupport?.('header'));

  // A new name or emoji slides in, as when the agent names the chat after its first answer
  const titleSignature = `${icon ?? ''}\u0000${title ?? ''}\u0000${subtitle ?? ''}`;
  const titleKeyRef = useRef({ signature: titleSignature, key: 0 });
  if (titleKeyRef.current.signature !== titleSignature) {
    titleKeyRef.current = { signature: titleSignature, key: titleKeyRef.current.key + 1 };
  }

  return (
    <div
      ref={ref}
      className={buildClassName(styles.header, hasAccessory && styles.headerOverBackdrop, isScrolled && 'is-scrolled')}
      data-agent-header
    >
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
      {titleContent ?? (
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
      )}
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
              <i className={buildClassName('icon-menu-params', styles.settingsIcon)} aria-hidden />
            </Button>
          ) : (
            <>
              {onRequestSupport && (
                <Button
                  isSimple
                  isText
                  kind="transparent"
                  className={buildClassName(styles.menuButton, styles.supportButton)}
                  ariaLabel={lang('$agent_support_contact')}
                  isDisabled={!canRequestSupport}
                  onClick={handleRequestSupport}
                >
                  <AgentSupportIcon className={styles.supportIcon} />
                </Button>
              )}
              {Boolean(onReportProblem || onDelete) && (
                <AgentMenu
                  className={styles.menuButton}
                  menuClassName={styles.menu}
                  getContainer={getHeader}
                  onReportProblem={onReportProblem}
                  onDelete={onDelete}
                />
              )}
            </>
          )}
        </div>
      ) : <div className={styles.menuPlaceholder} />}
    </div>
  );
}

export default memo(AgentHeader);
