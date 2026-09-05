import React, { memo } from '../../lib/teact/teact';

import type { MarketToken } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';
import { getIsRwaStockToken } from '../../util/tokens';

import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import TokenLabel from '../common/TokenLabel';
import TokenChange from './TokenChange';

import styles from './Market.module.scss';

interface OwnProps {
  token: MarketToken;
  onClick: (slug: string) => void;
}

function TokenRow({ token, onClick }: OwnProps) {
  const { slug, token: apiToken, priceText, change } = token;

  const handleClick = useLastCallback(() => {
    onClick(slug);
  });

  return (
    <button type="button" className={buildClassName(styles.row, styles.interactive)} onClick={handleClick}>
      <TokenIcon token={apiToken} size="large" withChainIcon />
      <span className={styles.rowText}>
        <span className={styles.rowTitle}>
          {apiToken.symbol}
          {Boolean(apiToken.label) && <TokenLabel label={apiToken.label} isRwaStock={getIsRwaStockToken(apiToken)} />}
        </span>
        <span className={styles.rowSubtitle}>
          {priceText}
          <TokenChange change={change} />
        </span>
      </span>
      <i className={buildClassName(styles.rowChevron, 'icon-chevron-right')} aria-hidden />
    </button>
  );
}

export default memo(TokenRow);
