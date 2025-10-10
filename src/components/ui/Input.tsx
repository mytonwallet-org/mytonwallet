import type { ClipboardEvent, FormEvent, HTMLAttributes, KeyboardEvent, RefObject,
} from 'react';
import type { ElementRef, TeactNode } from '../../lib/teact/teact';
import { useLayoutEffect, useRef } from '../../lib/teact/teact';
import React, { memo, useState } from '../../lib/teact/teact';

import { forceMeasure } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';

import styles from './Input.module.scss';

type OwnProps = {
  ref?: ElementRef<HTMLInputElement | HTMLTextAreaElement>;
  id?: string;
  type?: 'text' | 'password';
  label?: TeactNode;
  placeholder?: string;
  valueOverlay?: TeactNode;
  value?: string | number;
  inputMode?: 'numeric' | 'text' | 'search';
  maxLength?: number;
  isRequired?: boolean;
  isDisabled?: boolean;
  isMultiline?: boolean;
  hasError?: boolean;
  error?: string;
  className?: string;
  wrapperClassName?: string;
  autoCapitalize?: string;
  autoComplete?: string;
  autoCorrect?: boolean;
  isStatic?: boolean;
  enterKeyHint?: HTMLAttributes<HTMLInputElement>['enterKeyHint'];
  inputArg?: any;
  children?: TeactNode;
  onInput: (value: string, inputArg?: any) => void;
  onPaste?: (e: ClipboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onKeyDown?: (e: KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onFocus?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onBlur?: (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
};

function Input({
  ref,
  id,
  label,
  placeholder,
  valueOverlay,
  inputMode,
  isRequired,
  isDisabled,
  isMultiline,
  hasError,
  type = 'text',
  error,
  value = '',
  maxLength,
  inputArg,
  className,
  wrapperClassName,
  autoCapitalize,
  autoComplete,
  autoCorrect,
  isStatic,
  enterKeyHint,
  children,
  onInput,
  onPaste,
  onKeyDown,
  onFocus,
  onBlur,
}: OwnProps) {
  const lang = useLang();
  const [isPasswordVisible, setIsPasswordVisible] = useState<boolean>(false);
  const [hasFocus, markHasFocus, unmarkHasFocus] = useFlag(false);

  let inputRef = useRef<HTMLInputElement | HTMLTextAreaElement>();
  if (ref) {
    inputRef = ref;
  }

  const showValueOverlay = Boolean(valueOverlay && !hasFocus);

  const handleInput = (e: FormEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    onInput(e.currentTarget.value, inputArg);
  };

  const handleTogglePasswordVisibility = () => {
    setIsPasswordVisible(!isPasswordVisible);
  };

  useLayoutEffect(() => {
    if (!isMultiline) return;

    const textareaEl = inputRef.current as HTMLTextAreaElement | undefined;
    if (textareaEl) {
      updateTextAreaHeight(textareaEl);
    }
  }, [isMultiline, value]);

  const handleFocus = (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    markHasFocus();
    onFocus?.(e);
  };

  const handleBlur = (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    unmarkHasFocus();
    onBlur?.(e);
  };

  const finalType = type === 'text' || isPasswordVisible ? 'text' : 'password';
  const inputFullClass = buildClassName(
    styles.input,
    className,
    type === 'password' && styles.input_password,
    (hasError || error) && styles.error,
    isDisabled && styles.disabled,
    valueOverlay && styles.input_withvalueOverlay,
  );
  const labelFullClass = buildClassName(
    styles.label,
    (hasError || error) && styles.error,
    (hasError || error) && type === 'password' && styles.label_forPassword,
  );

  return (
    <div className={buildClassName(styles.wrapper, wrapperClassName)}>
      {error && !!label && (
        <label className={buildClassName(styles.label, styles.label_error, styles.error)} htmlFor={id}>{error}</label>
      )}
      {!!label && (
        <label className={labelFullClass} htmlFor={id}>
          {label}
        </label>
      )}
      <div className={styles.inputContainer}>
        {isMultiline ? (
          <textarea
            ref={inputRef as RefObject<HTMLTextAreaElement>}
            id={id}
            className={inputFullClass}
            value={value}
            disabled={isDisabled}
            maxLength={maxLength}
            autoComplete={autoComplete}
            onInput={handleInput}
            onPaste={onPaste}
            onKeyDown={onKeyDown}
            onFocus={handleFocus}
            onBlur={handleBlur}
            tabIndex={0}
            required={isRequired}
            placeholder={valueOverlay ? undefined : placeholder}
          />
        ) : (
          <input
            ref={inputRef as RefObject<HTMLInputElement>}
            id={id}
            className={inputFullClass}
            type={finalType}
            value={value}
            disabled={isDisabled}
            inputMode={inputMode}
            maxLength={maxLength}
            autoCapitalize={autoCapitalize}
            autoComplete={autoComplete}
            autoCorrect={autoCorrect}
            spellCheck={autoCorrect}
            onInput={handleInput}
            onPaste={onPaste}
            onKeyDown={onKeyDown}
            onFocus={handleFocus}
            onBlur={handleBlur}
            tabIndex={0}
            required={isRequired}
            placeholder={valueOverlay ? undefined : placeholder}
            enterKeyHint={enterKeyHint}
          />
        )}

        {showValueOverlay && (
          <div className={buildClassName(styles.valueOverlay, isStatic && styles.static)}>
            {valueOverlay}
          </div>
        )}
      </div>

      {type === 'password' && (
        <button
          className={buildClassName(styles.visibilityToggle, label && styles.visibilityToggle_push)}
          type="button"
          onClick={handleTogglePasswordVisibility}
          aria-label={lang('Change password visibility')}
          tabIndex={-1}
        >
          <i className={isPasswordVisible ? 'icon-eye' : 'icon-eye-closed'} aria-hidden />
        </button>
      )}
      {children}
      {error && !label && (
        <label className={buildClassName(styles.label, styles.label_errorBottom, styles.error)} htmlFor={id}>
          {error}
        </label>
      )}
    </div>
  );
}

export default memo(Input);

function updateTextAreaHeight(el: HTMLTextAreaElement) {
  forceMeasure(() => {
    el.style.height = '0';
    el.style.height = `${el.scrollHeight}px`;
  });
}
