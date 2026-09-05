import React, { memo } from '../../lib/teact/teact';

import type { MarketToken } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import TokenChange from './TokenChange';

import styles from './Market.module.scss';

interface OwnProps {
  token: MarketToken;
  onClick: (slug: string) => void;
}

function GridItem({ token, onClick }: OwnProps) {
  const { slug, token: apiToken, name, change } = token;

  const handleClick = useLastCallback(() => {
    onClick(slug);
  });

  return (
    <button type="button" className={buildClassName(styles.gridItem, styles.interactive)} onClick={handleClick}>
      <TokenIcon token={apiToken} size="xx-large" withChainIcon />
      <span className={styles.gridItemName}>{name}</span>
      <TokenChange change={change} />
    </button>
  );
}

export default memo(GridItem);
