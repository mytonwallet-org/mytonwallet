import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { TokenChartMode, UserToken } from '../../global/types';
import type { TokenBalanceChange } from './helpers/resolveBalanceChange';

import buildClassName from '../../util/buildClassName';

import useHeightChange from '../../hooks/useHeightChange';

import TopActions from '../main/sections/Actions/TopActions';
import Balance from './sections/Balance';
import Chart from './sections/Chart';
import Info from './sections/Info';

import styles from './Summary.module.scss';

interface OwnProps {
  token: UserToken;
  isActive?: boolean;
  className?: string;
  onHeightChange: (prevHeight: number, nextHeight: number) => void;
}

function Summary({
  token, isActive, className, onHeightChange,
}: OwnProps) {
  const rootRef = useRef<HTMLDivElement>();
  const [chartMode, setChartMode] = useState<TokenChartMode>('price');
  // The balance follows the point under the cursor, so the chart reports the change up to here
  const [balanceChange, setBalanceChange] = useState<TokenBalanceChange>();

  const { slug } = token;

  useHeightChange(rootRef, onHeightChange);

  return (
    <div ref={rootRef} className={buildClassName(styles.root, className)}>
      <Balance token={token} change={balanceChange} />

      <TopActions tokenSlug={slug} isActive={isActive} className={styles.actions} />

      <div className={styles.panels}>
        <Chart
          token={token}
          chartMode={chartMode}
          isActive={isActive}
          className={styles.panel}
          onChartModeChange={setChartMode}
          onBalanceChangeUpdate={setBalanceChange}
        />
        <Info tokenSlug={slug} isActive={isActive} className={styles.panel} />
      </div>
    </div>
  );
}

export default memo(Summary);
