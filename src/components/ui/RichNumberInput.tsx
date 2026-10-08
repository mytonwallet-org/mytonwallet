import type { RefObject, TeactNode } from '../../lib/teact/teact';
import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';

import { FRACTION_DIGITS } from '../../config';
import buildClassName from '../../util/buildClassName';
import { saveCaretPosition } from '../../util/saveCaretPosition';
import { buildContentHtml } from './helpers/buildContentHtml';

import { useCombinedRefs } from '../../hooks/useCombinedRef';
import useFlag from '../../hooks/useFlag';
import useFontScale from '../../hooks/useFontScale';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import styles from './Input.module.scss';

type OwnProps = {
  ref?: RefObject<HTMLInputElement | undefined>;
  id?: string;
  labelText?: TeactNode;
  value?: string;
  hasError?: boolean;
  isLoading?: boolean;
  prefix?: string;
  suffix?: string;
  className?: string;
  inputClassName?: string;
  labelClassName?: string;
  valueClassName?: string;
  cornerClassName?: string;
  children?: TeactNode;
  onChange?: (value?: string) => void;
  onBlur?: NoneToVoidFunction;
  onFocus?: NoneToVoidFunction;
  onPressEnter?: (e: React.KeyboardEvent<HTMLDivElement>) => void;
  /** Expected to fire when regardless of the `disabled` prop value */
  onInputClick?: NoneToVoidFunction;
  decimals?: number;
  disabled?: boolean;
  size?: 'large' | 'normal';
};

const MIN_LENGTH_FOR_SHRINK = 5;

function RichNumberInput({
  ref,
  id,
  labelText,
  hasError,
  isLoading = false,
  prefix = '',
  suffix = '',
  value,
  children,
  className,
  inputClassName,
  labelClassName,
  valueClassName,
  cornerClassName,
  onChange,
  onBlur,
  onFocus,
  onPressEnter,
  onInputClick,
  decimals = FRACTION_DIGITS,
  disabled = false,
  size = 'large',
}: OwnProps) {
  const inputRef = useRef<HTMLInputElement>();
  const placeholderRef = useRef<HTMLDivElement>();
  const lang = useLang();
  const combinedRef = useCombinedRefs<HTMLDivElement>(inputRef, ref);

  const [hasFocus, markHasFocus, unmarkHasFocus] = useFlag(false);
  const { updateFontScale, isFontChangedRef } = useFontScale(inputRef);

  const textRef = useRef('');

  const updateHtml = useLastCallback((newText: string) => {
    const input = inputRef.current!;
    const html = buildContentHtml(newText, prefix, suffix, decimals);

    // Don't use the :empty pseudo-class to hide the placeholder, because it's noticeable delayed on iOS
    placeholderRef.current!.innerHTML = newText ? '' : buildContentHtml('0', prefix, suffix);

    if (html !== input.innerHTML) {
      const restoreCaretPosition = document.activeElement === input
        ? saveCaretPosition(input, prefix.length, decimals)
        : undefined;

      input.innerHTML = html;
      restoreCaretPosition?.();
    }

    if (`${prefix}${newText}${suffix}`.length > MIN_LENGTH_FOR_SHRINK || isFontChangedRef.current) {
      updateFontScale();
    }
  });

  useLayoutEffect(() => {
    const newText = clearText(value);
    // While the field is focused, its text may be a spelling of `value` that is still being typed: `1.` or `1.50`
    // for the value `1` or `1.5`. Rewriting the field from the value would eat what has just been typed, so such
    // text is kept. Without focus the value wins, because it may have been set from outside, for example by a
    // percent button. `handleBlur` applies the same rule when the focus leaves.
    const shouldKeepTypedText = Boolean(newText)
      && document.activeElement === inputRef.current
      && textRef.current.startsWith(newText);

    if (!shouldKeepTypedText) {
      updateHtml(newText);
      textRef.current = newText;
    }
  }, [textRef, value]);

  useLayoutEffect(() => {
    updateHtml(textRef.current);
  }, [prefix, suffix, decimals]);

  function handleChange(e: React.FormEvent<HTMLDivElement>) {
    const newText = clearText(e.currentTarget.textContent ?? undefined);

    updateHtml(newText);

    if (newText !== textRef.current) {
      textRef.current = newText;

      if (onChange && isValidValue(newText)) {
        onChange(newText);
      }
    }
  }

  const handleFocus = useLastCallback(() => {
    if (disabled) return;

    markHasFocus();
    onFocus?.();
  });

  const handleBlur = useLastCallback(() => {
    if (disabled) return;

    unmarkHasFocus();

    // Typed text that has not been accepted as a value gives way to the value
    const text = clearText(value);
    if (text !== textRef.current) {
      updateHtml(text);
      textRef.current = text;
    }

    onBlur?.();
  });

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Enter') {
      onPressEnter?.(e);
    }
  };

  const inputWrapperFullClass = buildClassName(
    styles.input__wrapper,
    size === 'large' && styles.input__wrapper_large,
    hasError && styles.error,
    hasFocus && styles.input__wrapper_hasFocus,
    inputClassName,
  );
  const inputFullClass = buildClassName(
    styles.input,
    size === 'large' && styles.large,
    valueClassName,
    disabled && styles.disabled,
    isLoading && styles.isLoading,
    'rounded-font',
  );
  const labelTextClassName = buildClassName(
    styles.label,
    hasError && styles.error,
    labelClassName,
  );
  const cornerFullClass = buildClassName(
    cornerClassName,
    hasFocus && styles.swapCorner,
    hasError && styles.swapCorner_error,
  );

  return (
    <div className={buildClassName(styles.wrapper, className)}>
      {Boolean(labelText) && (
        <label
          className={labelTextClassName}
          htmlFor={id}
          id={`${id}Label`}
        >
          {labelText}
        </label>
      )}
      <div className={inputWrapperFullClass}>
        <div className={styles.rich}>
          <div
            ref={combinedRef}
            contentEditable={!disabled && !isLoading}
            id={id}
            role="textbox"
            aria-required
            aria-placeholder={lang('Amount value')}
            aria-labelledby={labelText ? `${id}Label` : undefined}
            tabIndex={0}
            inputMode="decimal"
            className={buildClassName(inputFullClass, styles.rich__value)}
            onKeyDown={handleKeyDown}
            onChange={handleChange}
            onFocus={handleFocus}
            onBlur={handleBlur}
            onClick={onInputClick}
          />
          <div
            ref={placeholderRef}
            className={buildClassName(inputFullClass, styles.rich__placeholder)}
          />
        </div>
        {children}
      </div>
      {cornerClassName && <div className={cornerFullClass} />}
    </div>
  );
}

function clearText(text?: string) {
  if (!text) return '';

  return (
    text
      .trim()
      .replace(',', '.') // Replace comma to point
      .replace(/[^\d.]/g, '') // Remove incorrect symbols
      .replace(/^0+(?=([1-9]|0\.))/, '') // Trim extra zeros at beginning
      .replace(/^0+$/, '0') // Trim extra zeros (if only zeros are entered)
      ?? ''
  );
}

function isValidValue(text: string) {
  return !Number.isNaN(Number(text));
}

export default memo(RichNumberInput);

export function focusAtTheEnd(inputId: string) {
  const input = document.getElementById(inputId);
  const selection = window.getSelection();
  if (!input || !selection) {
    return;
  }

  const range = document.createRange();
  range.selectNodeContents(input);
  range.collapse(false);
  selection.removeAllRanges();
  selection.addRange(range);
}
