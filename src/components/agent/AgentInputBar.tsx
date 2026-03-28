import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Input from '../ui/Input';

import styles from './AgentInputBar.module.scss';

interface OwnProps {
  inputRef?: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  hints?: AgentHint[];
  isScrolledUp?: boolean;
  onInput: (value: string) => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  onClearInput: NoneToVoidFunction;
  onHintsToggle: NoneToVoidFunction;
}

function AgentInputBar({
  inputRef: externalInputRef, inputValue, hints, isScrolledUp,
  onInput, onKeyDown, onSend, onClearInput, onHintsToggle,
}: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const ownInputRef = useRef<HTMLTextAreaElement>();
  const inputRef = externalInputRef || ownInputRef;
  const wrapperRef = useRef<HTMLDivElement>();
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

  const { ref: sendButtonWrapperRef } = useShowTransition<HTMLDivElement>({
    isOpen: !!inputValue,
    noMountTransition: true,
  });

  return (
    <div
      ref={wrapperRef}
      className={buildClassName(styles.wrapper, (isScrolledUp || isPortrait) && styles.withSeparator)}
    >
      <div className={styles.inputBar}>
        <div className={styles.inputField}>
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
          {inputValue ? (
            <button
              type="button"
              className={styles.inputButton}
              aria-label={lang('Clear')}
              onClick={onClearInput}
            >
              <i className="icon-clear" aria-hidden />
            </button>
          ) : hints?.length ? (
            <button
              type="button"
              className={styles.inputButton}
              aria-label={lang('Toggle Hints')}
              onClick={onHintsToggle}
            >
              <i className="icon-agent-actions" aria-hidden />
            </button>
          ) : undefined}
        </div>

        <div ref={sendButtonWrapperRef} className={styles.sendButtonWrapper}>
          <button
            type="submit"
            className={styles.sendButton}
            onClick={onSend}
          >
            <i className="icon-send-alt2" aria-hidden />
          </button>
        </div>
      </div>
    </div>
  );
}

export default memo(AgentInputBar);
