import React, { memo } from '../../lib/teact/teact';

import type { MarketToken } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { hex2rgb } from '../../util/colors';

import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import Sparkline from './Sparkline';
import TokenChange from './TokenChange';

import styles from './Market.module.scss';

interface OwnProps {
  token: MarketToken;
  onClick: (slug: string) => void;
}

function MoverCard({ token, onClick }: OwnProps) {
  const { slug, token: apiToken, name, priceText, change, sparkline, tintColor } = token;

  const handleClick = useLastCallback(() => {
    onClick(slug);
  });

  // The tint paints the card background and the chart, at different opacities per theme
  const style = tintColor ? buildStyle(`--market-tint-rgb: ${hex2rgb(tintColor).join(' ')}`) : undefined;

  return (
    <button type="button" className={buildClassName(styles.card, styles.moverCard)} style={style} onClick={handleClick}>
      {sparkline && <Sparkline points={sparkline} />}
      <TokenIcon token={apiToken} withChainIcon iconClassName={styles.moverIcon} />
      <span className={styles.moverName}>{name}</span>
      <span className={styles.moverPrice}>
        {priceText}
        <TokenChange change={change} />
      </span>
    </button>
  );
}

export default memo(MoverCard);
