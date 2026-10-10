import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';

import type { AgentUserQuotaV2 } from '../../api/agentV2/protocol/types';

import { requestMeasure } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Input from '../ui/Input';

import styles from './AgentInputBar.module.scss';

interface OwnProps {
  inputRef?: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  userQuota?: AgentUserQuotaV2;
  quotaStatus?: TeactNode;
  statusNotice?: TeactNode;
  /** Blocks sending only; the draft stays editable while an answer is running */
  isDisabled?: boolean;
  onInput: (value: string) => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  onHeightChange?: (height: number) => void;
}

function AgentInputBar({
  inputRef: externalInputRef, inputValue, userQuota, quotaStatus, statusNotice, isDisabled,
  onInput, onKeyDown, onSend, onHeightChange,
}: OwnProps) {
  const lang = useLang();
  const [isQuotaVisible, setIsQuotaVisible] = useState(false);
  const ownInputRef = useRef<HTMLTextAreaElement>();
  const wrapperRef = useRef<HTMLDivElement>();
  const inputRef = externalInputRef || ownInputRef;
  const savedScrollRef = useRef({ top: 0, isCaretAtEnd: true });

  // Save scroll state and caret position before re-render triggers Input's resize
  const handleInput = useLastCallback((value: string) => {
    const el = inputRef.current;
    if (el) {
      savedScrollRef.current = {
        top: el.scrollTop,
        isCaretAtEnd: el.selectionEnd === el.value.length,
      };
    }
    onInput(value);
  });

  // After Input's resize resets `scrollTop` to 0, restore scroll position
  useEffect(() => {
    const el = inputRef.current;
    if (!el || el.scrollHeight <= el.clientHeight) return;

    const { top, isCaretAtEnd } = savedScrollRef.current;
    if (isCaretAtEnd) {
      el.scrollTop = el.scrollHeight;
    } else {
      el.scrollTop = Math.min(top, el.scrollHeight - el.clientHeight);
    }
  }, [inputRef, inputValue]);

  useLayoutEffect(() => {
    const element = wrapperRef.current;
    if (!element || !onHeightChange) return undefined;

    const notifyHeightChange = () => {
      requestMeasure(() => {
        if (element.isConnected) {
          onHeightChange(element.offsetHeight);
        }
      });
    };
    const observer = new ResizeObserver(notifyHeightChange);
    observer.observe(element);
    notifyHeightChange();

    return () => observer.disconnect();
  }, [onHeightChange]);

  const { ref: sendButtonRef } = useShowTransition<HTMLButtonElement>({
    isOpen: !!inputValue,
    noMountTransition: true,
    className: false,
  });

  const handleQuotaToggle = useLastCallback(() => {
    setIsQuotaVisible(!isQuotaVisible);
  });

  return (
    <div ref={wrapperRef} className={styles.wrapper}>
      {statusNotice !== undefined && (
        <div className={styles.statusSlot}>
          {statusNotice}
        </div>
      )}
      {isQuotaVisible && quotaStatus !== undefined && (
        <div className={styles.quotaSlot}>
          {quotaStatus}
        </div>
      )}
      <div className={styles.inputRow}>
        <div className={styles.pill}>
          <Input
            ref={inputRef}
            isMultiline
            value={inputValue}
            placeholder={lang('Ask anything')}
            className={styles.input}
            wrapperClassName={styles.inputInnerWrapper}
            onInput={handleInput}
            onKeyDown={onKeyDown}
          />
          {userQuota && (
            <div className={styles.inputButtons}>
              <button
                type="button"
                className={buildClassName(styles.inputButton, isQuotaVisible && styles.inputButtonActive)}
                aria-expanded={isQuotaVisible}
                aria-label={lang(
                  '$agent_user_quota_meter',
                  [userQuota.remaining, userQuota.limit],
                ) as string}
                onClick={handleQuotaToggle}
              >
                <i className="icon-question" aria-hidden />
              </button>
            </div>
          )}
        </div>
        <button
          ref={sendButtonRef}
          type="submit"
          className={styles.sendButton}
          aria-label={lang('Send')}
          disabled={isDisabled}
          onClick={onSend}
        >
          <i className="icon-send-alt2" aria-hidden />
        </button>
      </div>
    </div>
  );
}

export default memo(AgentInputBar);
