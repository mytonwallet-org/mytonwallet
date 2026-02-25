import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useLayoutEffect, useRef } from '../../lib/teact/teact';

import type { SensitiveDataMaskSkin } from '../common/SensitiveDataMask';

import { FRACTION_DIGITS } from '../../config';
import { getNumberRegex } from '../../global/helpers/number';
import buildClassName from '../../util/buildClassName';
import { buildContentHtml } from './helpers/buildContentHtml';

import useFontScale from '../../hooks/useFontScale';
import useLastCallback from '../../hooks/useLastCallback';

import SensitiveData from './SensitiveData';

import styles from './Input.module.scss';

type OwnProps = {
  id?: string;
  labelText?: string;
  value?: string;
  error?: string;
  prefix?: string;
  suffix?: string;
  zeroValue?: string;
  decimals?: number;
  className?: string;
  isSensitiveData?: true;
  isSensitiveDataHidden?: true;
  sensitiveDataMaskSkin?: SensitiveDataMaskSkin;
  isStatic?: boolean;
  inputClassName?: string;
  labelClassName?: string;
  valueClassName?: string;
  children?: TeactNode;
};

const MIN_LENGTH_FOR_SHRINK = 5;

function RichNumberField({
  id,
  labelText,
  value,
  error,
  prefix,
  suffix,
  zeroValue,
  decimals = FRACTION_DIGITS,
  className,
  isSensitiveData,
  isSensitiveDataHidden,
  sensitiveDataMaskSkin,
  isStatic,
  inputClassName,
  labelClassName,
  valueClassName,
  children,
}: OwnProps) {
  const contentRef = useRef<HTMLInputElement>();
  const prevValueRef = useRef<string>('');
  const { updateFontScale, isFontChangedRef } = useFontScale(contentRef, true);

  const renderValue = useLastCallback((inputValue = '', noFallbackToPrev = false) => {
    const contentEl = contentRef.current!;

    const valueRegex = getNumberRegex(decimals);
    const values = inputValue.match(valueRegex);

    // eslint-disable-next-line no-null/no-null
    if (values === null || values.length < 4 || values[0] === '') {
      if (noFallbackToPrev || inputValue === '') {
        prevValueRef.current = '';
        contentEl.innerText = '';
      } else {
        renderValue(prevValueRef.current, true);
      }

      return;
    }
    const textContent = values?.[0] || '';
    prevValueRef.current = inputValue;

    contentEl.innerHTML = buildContentHtml(inputValue, prefix, suffix, decimals, true);

    if (textContent.length > MIN_LENGTH_FOR_SHRINK || isFontChangedRef.current) {
      updateFontScale();
    }
  });

  useLayoutEffect(() => {
    if (value) {
      renderValue(value);
    } else if (zeroValue) {
      contentRef.current!.textContent = zeroValue;
    }
  }, [prefix, suffix, decimals, renderValue, value, zeroValue]);

  const inputWrapperFullClass = buildClassName(
    styles.input__wrapper,
    isStatic && styles.inputWrapperStatic,
    inputClassName,
  );
  const inputFullClass = buildClassName(
    styles.rich__value,
    styles.input,
    styles.large,
    styles.disabled,
    error && styles.error,
    'rounded-font',
    valueClassName,
  );
  const labelTextClassName = buildClassName(
    styles.label,
    labelClassName,
  );

  return (
    <div className={buildClassName(styles.wrapper, className)}>
      {error && (
        <label className={buildClassName(styles.label, styles.label_error, styles.error)} htmlFor={id}>{error}</label>
      )}
      {labelText && (
        <label
          className={labelTextClassName}
          htmlFor={id}
          id={`${id}Label`}
        >
          {labelText}
        </label>
      )}
      <div className={inputWrapperFullClass}>
        {isSensitiveData ? (
          <SensitiveData
            isActive={isSensitiveDataHidden}
            cols={8}
            rows={3}
            cellSize={16}
            maskSkin={sensitiveDataMaskSkin}
            // Adding `.large` to remove the excessive bottom padding created by SensitiveData (the `height` property does the job)
            className={buildClassName(styles.rich, styles.large)}
            contentClassName={styles.richContent}
            maskClassName={styles.mask}
          >
            <div ref={contentRef} id={id} className={inputFullClass} />
          </SensitiveData>
        ) : (
          <div className={styles.rich}>
            <div ref={contentRef} id={id} className={inputFullClass} />
          </div>
        )}
        {children}
      </div>
    </div>
  );
}

export default memo(RichNumberField);
