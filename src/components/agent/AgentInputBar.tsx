import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { AgentHint } from '../../global/types';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Input from '../ui/Input';

import styles from './AgentInputBar.module.scss';

interface OwnProps {
  inputRef?: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  hints?: AgentHint[];
  onInput: (value: string) => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  onClearInput: NoneToVoidFunction;
  onHintsToggle: NoneToVoidFunction;
}

function AgentInputBar({
  inputRef: externalInputRef, inputValue, hints,
  onInput, onKeyDown, onSend, onClearInput, onHintsToggle,
}: OwnProps) {
  const lang = useLang();
  const ownInputRef = useRef<HTMLTextAreaElement>();
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

  const { ref: sendButtonRef } = useShowTransition<HTMLButtonElement>({
    isOpen: !!inputValue,
    noMountTransition: true,
    className: false,
  });

  const shouldRenderHints = !inputValue && !!hints?.length;

  return (
    <div className={styles.wrapper}>
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
        {inputValue ? (
          <button
            type="button"
            className={styles.inputButton}
            aria-label={lang('Clear')}
            onClick={onClearInput}
          >
            <i className="icon-clear" aria-hidden />
          </button>
        ) : shouldRenderHints && (
          <button
            type="button"
            className={styles.inputButton}
            aria-label={lang('Toggle Hints')}
            onClick={onHintsToggle}
          >
            <i className="icon-agent-actions" aria-hidden />
          </button>
        )}
      </div>
      <button
        ref={sendButtonRef}
        type="submit"
        className={styles.sendButton}
        aria-label={lang('Send')}
        onClick={onSend}
      >
        <i className="icon-send-alt2" aria-hidden />
      </button>
    </div>
  );
}

export default memo(AgentInputBar);
