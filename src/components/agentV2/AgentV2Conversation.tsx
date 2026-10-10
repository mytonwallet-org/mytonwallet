import React, {
  useEffect, useState,
} from '../../lib/teact/teact';

import type { AnswerTableProps } from '../agent/AnswerMessageContent';
import type { TextRevealPresentation } from '../agent/hooks/textRevealPresentation';

import { APP_NAME } from '../../config';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import StaticText from '../agent/StaticText';
import StreamingText from '../agent/StreamingText';
import Button from '../ui/Button';

import styles from './AgentV2Conversation.module.scss';

export function AgentV2ConsentScreen({ onAccept }: { onAccept: NoneToVoidFunction }) {
  const lang = useLang();
  return (
    <div className={styles.consent}>
      <div className={styles.consentScroll}>
        <div className={styles.consentContent}>
          <div className={styles.consentIntro}>
            <div className={styles.consentIcon}><i className="icon-agent" aria-hidden /></div>
            <h2 className={styles.consentTitle}>{lang('Data shared with Agent')}</h2>
            <p className={styles.consentSubtitle}>{lang('$agent_consent_subtitle')}</p>
          </div>

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
            <p className={styles.disclosureText}>{lang('$agent_consent_search_disclosure_text')}</p>
          </div>
        </div>
      </div>

      <div className={styles.consentFooter}>
        <Button className={styles.consentButton} isPrimary onClick={onAccept}>
          {lang('$agent_consent_allow_button')}
        </Button>
      </div>
    </div>
  );
}

export function AgentV2AssistantText({
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
