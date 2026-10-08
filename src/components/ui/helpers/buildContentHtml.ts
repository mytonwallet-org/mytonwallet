import { FRACTION_DIGITS, WHOLE_PART_DELIMITER } from '../../../config';

import styles from '../Input.module.scss';

export function buildContentHtml(
  text: string,
  prefix = '',
  suffix = '',
  decimals = FRACTION_DIGITS,
  withRadix = false,
) {
  text = sanitizeHtml(text);
  prefix = sanitizeHtml(prefix);
  suffix = sanitizeHtml(suffix);

  if (!text) {
    return '';
  }

  const hasDot = text.includes('.');
  const [wholePart = '0', fractionPart] = hasDot ? text.split('.') : [text];

  const formattedWholePart = withRadix
    ? wholePart.replace(/\d(?=(\d{3})+($|\.))/g, `$&${WHOLE_PART_DELIMITER}`)
    : wholePart;
  const fractionStr = hasDot ? `.${(fractionPart || '').substring(0, decimals)}` : '';
  const suffixStr = suffix ? `&thinsp;${suffix}` : '';
  const extraSpan = fractionStr || suffixStr ? (
    `<span class="${styles.fractional}">${fractionStr}${suffixStr}</span>`
  ) : '';
  const prefixSpan = prefix ? `<span class="${styles.prefix}">${prefix}</span>` : '';

  return `${prefixSpan}${formattedWholePart}${extraSpan}`;
}

function sanitizeHtml(string: string) {
  const tempEl = document.createElement('span');
  tempEl.textContent = string;
  return tempEl.innerHTML;
}
