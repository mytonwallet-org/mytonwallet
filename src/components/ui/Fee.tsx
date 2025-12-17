import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiToken } from '../../api/types';
import type { FeePrecision, FeeTerms, FeeValue } from '../../util/fee/types';

import { STARS_SYMBOL, TOKEN_CUSTOM_STYLES } from '../../config';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { findNativeToken, getChainBySlug } from '../../util/tokens';

import styles from './Fee.module.scss';

const TERM_SEPARATOR = ' + ';
const PRECISION_PREFIX: Record<FeePrecision, string> = {
  exact: '',
  approximate: '~\u202F',
  lessThan: '<\u202F',
};
const STARS_TOKEN: FeeToken = {
  slug: '__stars__',
  symbol: STARS_SYMBOL,
  decimals: 0,
};
const UNKNOWN_TOKEN: FeeToken = {
  slug: '__unknown__',
  symbol: '',
  decimals: 0,
};

export type FeeToken = Pick<ApiToken, 'slug' | 'symbol' | 'decimals'>;

type FeeListTerm = {
  tokenType: keyof FeeTerms;
  amount: FeeValue;
};

export type OwnProps = {
  terms: FeeTerms;
  /** The token acting as the transferred token in the `terms` object */
  token: FeeToken;
  /** Affects the sign indicating the fee precision and standing before the terms. */
  precision: FeePrecision;
  shouldPreferIcons?: boolean;
  termClassName?: string;
  symbolClassName?: string;
};

/**
 * Formats a complex fee (containing multiple terms) into a human-readable span
 */
function Fee({
  terms,
  token,
  precision,
  shouldPreferIcons,
  termClassName,
  symbolClassName,
}: OwnProps) {
  const nativeToken = findNativeToken(getChainBySlug(token.slug)) ?? UNKNOWN_TOKEN;
  const content: TeactNode[] = [PRECISION_PREFIX[precision]];

  convertTermsObjectToList(terms).forEach(({ tokenType, amount }, index) => {
    if (index > 0) {
      content.push(TERM_SEPARATOR);
    }

    const currentToken = tokenType === 'stars' ? STARS_TOKEN : tokenType === 'native' ? nativeToken : token;
    const icon = shouldPreferIcons ? TOKEN_CUSTOM_STYLES[currentToken.slug]?.fontIcon : undefined;

    if (typeof amount === 'bigint') {
      amount = toDecimal(amount, currentToken.decimals);
    }

    let symbolNode = icon
      ? <i className={buildClassName(icon, styles.tokenIcon)} aria-label={currentToken.symbol} />
      : currentToken.symbol;
    if (symbolClassName) {
      symbolNode = <span className={symbolClassName}>{symbolNode}</span>;
    }

    content.push(
      <span className={buildClassName(styles.term, termClassName)}>
        {formatCurrency(amount, '', undefined, true)}
        {symbolNode}
      </span>,
    );
  });

  return content;
}

export default memo(Fee);

function convertTermsObjectToList(terms: FeeTerms) {
  const termList: FeeListTerm[] = [];
  let firstDefinedTerm: FeeListTerm | undefined;

  for (const [tokenType, amount] of Object.entries(terms) as [keyof FeeTerms, bigint | undefined][]) {
    if (amount === undefined) {
      continue;
    }

    const term = { tokenType, amount };
    firstDefinedTerm ||= term;

    if (Number(amount)) {
      termList.push(term);
    }
  }

  // Keeping at least 1 term for better UX
  if (termList.length === 0) {
    termList.push(firstDefinedTerm ?? { tokenType: 'native', amount: 0 });
  }

  return termList;
}
