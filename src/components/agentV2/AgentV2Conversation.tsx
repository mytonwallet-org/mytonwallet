import React, {
  memo, useEffect, useState,
} from '../../lib/teact/teact';

import type { AnswerTableProps } from '../agent/AnswerMessageContent';
import type { TextRevealPresentation } from '../agent/hooks/textRevealPresentation';

import { APP_NAME, APP_PRIVACY_POLICY_URL } from '../../config';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentSpinningTop from '../agent/AgentSpinningTop';
import StaticText from '../agent/StaticText';
import StreamingText from '../agent/StreamingText';
import Button from '../ui/Button';
import Modal from '../ui/Modal';

import styles from './AgentV2Conversation.module.scss';

/**
 * The consent the Agent asks for at the first thing the user does that would send something to it: the app's bottom
 * sheet on mobile and its centred modal on desktop, under the app's sheet header with the Agent's name beside its
 * spinning top, the small one of the typing row. A hold grows the top threefold over the header, as everywhere, while
 * the title stays in place. The sheet sizes to its content up to the screen, past which the text scrolls above the
 * Allow button. Swiping it down, a tap outside it, the close button, Back or Escape closes it.
 */
export const AgentV2ConsentSheet = memo(({
  isOpen, isAllowing, onAllow, onClose,
}: {
  isOpen: boolean;
  isAllowing?: boolean;
  onAllow: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}) => {
  const lang = useLang();
  return (
    <Modal
      isOpen={isOpen}
      title={(
        <span className={styles.consentTitle}>
          <AgentSpinningTop
            className={styles.consentTitleIcon}
            markClassName={styles.consentTitleMark}
            isTouchInteractive
          />
          {lang('Agent')}
        </span>
      )}
      hasCloseButton
      forceBottomSheet
      dialogClassName={styles.consentDialog}
      contentClassName={styles.consent}
      onClose={onClose}
    >
      <div className={buildClassName(styles.consentScroll, 'custom-scroll')}>
        <div className={styles.consentContent}>
          <ul className={styles.consentList}>
            <li className={styles.consentFeature}>
              <span className={styles.consentFeatureIcon} aria-hidden>
                <i className="icon-question" />
              </span>
              <span className={styles.consentFeatureText}>
                {lang('$agent_consent_feature_answers', { app_name: APP_NAME })}
              </span>
            </li>
            <li className={styles.consentFeature}>
              <span className={styles.consentFeatureIcon} aria-hidden>
                <i className="icon-magic-wand" />
              </span>
              <span className={styles.consentFeatureText}>{lang('$agent_consent_feature_actions')}</span>
            </li>
            <li className={styles.consentFeature}>
              <span className={styles.consentFeatureIcon} aria-hidden>
                <i className="icon-wallet" />
              </span>
              <span className={styles.consentFeatureText}>{lang('$agent_consent_feature_context')}</span>
            </li>
          </ul>

          <div className={styles.disclosure}>
            <p className={styles.disclosureText}>
              {lang('$agent_consent_disclosure_text', { app_name: APP_NAME })}
            </p>
            <p className={styles.disclosureText}>
              {lang('$agent_consent_search_disclosure_text')}{' '}
              <a href={APP_PRIVACY_POLICY_URL} target="_blank" rel="noopener noreferrer">
                {lang('Learn more')}
              </a>
            </p>
          </div>
        </div>
      </div>

      <div className={styles.consentFooter}>
        <Button className={styles.consentButton} isPrimary isLoading={isAllowing} onClick={onAllow}>
          {lang('$agent_consent_allow_button')}
        </Button>
      </div>
    </Modal>
  );
});

function AssistantText({
  messageId,
  text,
  tables,
  tableReferences,
  links,
  isStreaming,
  shouldAnimate,
  shouldCommitMarkdownTail,
  textRevealPresentation,
  onTextRevealSessionConsumed,
  onTextRevealSessionSettled,
  onRevealProgress,
  onRevealComplete,
}: AnswerTableProps & {
  messageId: number;
  text: string;
  isStreaming: boolean;
  shouldAnimate: boolean;
  shouldCommitMarkdownTail?: boolean;
  textRevealPresentation?: TextRevealPresentation;
  onTextRevealSessionConsumed?: (messageId: number, key: string) => void;
  onTextRevealSessionSettled?: (messageId: number, key: string) => void;
  onRevealProgress?: NoneToVoidFunction;
  onRevealComplete?: NoneToVoidFunction;
}) {
  const activeTextRevealPresentation = textRevealPresentation?.status === 'active'
    ? textRevealPresentation
    : undefined;
  const [shouldRevealFromStart] = useState(
    Boolean(activeTextRevealPresentation?.shouldRevealFromStart),
  );
  useEffect(() => {
    if (!activeTextRevealPresentation?.shouldRevealFromStart) return;

    onTextRevealSessionConsumed?.(messageId, activeTextRevealPresentation.key);
  }, [activeTextRevealPresentation, messageId, onTextRevealSessionConsumed]);

  const handleRevealComplete = useLastCallback(() => {
    if (activeTextRevealPresentation) {
      onTextRevealSessionSettled?.(messageId, activeTextRevealPresentation.key);
    }
    onRevealComplete?.();
  });

  return (
    <div className={styles.answer}>
      {activeTextRevealPresentation ? (
        <StreamingText
          text={text}
          tables={tables}
          tableReferences={tableReferences}
          links={links}
          isStreaming={isStreaming}
          shouldAnimate={shouldAnimate}
          revealSessionKey={activeTextRevealPresentation.key}
          shouldRevealFromStart={shouldRevealFromStart}
          shouldCommitMarkdownTail={Boolean(shouldCommitMarkdownTail)}
          areLinksEnabled

          onRevealProgress={onRevealProgress}
          onRevealComplete={handleRevealComplete}
        />
      ) : (
        <StaticText text={text} tables={tables} tableReferences={tableReferences} links={links} areLinksEnabled />
      )}
    </div>
  );
}

export const AgentV2AssistantText = memo(AssistantText);
