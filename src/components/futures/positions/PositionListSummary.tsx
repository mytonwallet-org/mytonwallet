import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { Theme } from '../../../global/types';

import { Big } from '../../../lib/big.js';
import buildClassName from '../../../util/buildClassName';
import { formatNumber, formatPercent } from '../../../util/formatNumber';
import {
  formatPerpsSignedMoney,
  getPerpsRatioPercent,
  getPerpsValueTone,
  MISSING_VALUE,
  PERPS_CURRENCY_SYMBOL,
} from '../helpers/formatPerps';

import useAppTheme from '../../../hooks/useAppTheme';
import useCardController from '../../../hooks/useCardController';
import useIsMotionDisabled from '../../../hooks/useIsMotionDisabled';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import PrivacyDust from '../../common/PrivacyDust';
import Skeleton from '../../ui/Skeleton';

import styles from './PositionListSummary.module.scss';

interface OwnProps {
  /** Absent while the first snapshot has not loaded */
  totalEquity?: string;
  totalPnl?: string;
  totalReturnOnEquity?: string;
  /** Some books did not load, so the totals would understate the account */
  isIncomplete?: boolean;
  /** The first snapshot is on its way, so the total is a placeholder of its height */
  isLoading?: boolean;
}

interface StateProps {
  isSensitiveDataHidden?: true;
  theme: Theme;
  animationLevel: number;
}

function PositionListSummary({
  totalEquity, totalPnl, totalReturnOnEquity, isIncomplete, isLoading, isSensitiveDataHidden, theme, animationLevel,
}: OwnProps & StateProps) {
  const { setIsSensitiveDataHidden } = getActions();
  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const { cardRef, controller } = useCardController();
  const isMotionDisabled = useIsMotionDisabled(animationLevel);
  const [wholePart, fractionPart] = totalEquity !== undefined ? formatNumber(totalEquity).split('.') : [MISSING_VALUE];
  const pnlPercent = getPerpsRatioPercent(totalReturnOnEquity);
  // As on iOS, an account with open positions shows its profit and loss even when it is zero
  const isPnlShown = !isIncomplete && totalPnl !== undefined && totalEquity !== undefined && !Big(totalEquity).eq(0);
  const pnlTone = getPerpsValueTone(totalPnl);

  // As on the wallet card, a tap on the total hides the amounts or shows them again
  const handleTotalClick = useLastCallback(() => {
    setIsSensitiveDataHidden({ isHidden: !isSensitiveDataHidden });
  });

  function renderTotal() {
    if (isLoading) return <Skeleton className={styles.amountSkeleton} />;

    if (isIncomplete) return <p className={styles.incomplete}>{lang('PerpsIncompleteData')}</p>;

    return (
      <PrivacyDust
        isBalance
        isHidden={Boolean(isSensitiveDataHidden)}
        isDisabled={isMotionDisabled}
        controller={controller}
        revision={appTheme}
        className={styles.total}
        onClick={handleTotalClick}
      >
        <span className={buildClassName(styles.amount, 'rounded-font')}>
          <span className={styles.currency}>{PERPS_CURRENCY_SYMBOL}</span>
          {wholePart}
          {fractionPart && <span className={styles.fraction}>.{fractionPart}</span>}
        </span>
      </PrivacyDust>
    );
  }

  return (
    <section ref={cardRef} className={styles.root}>
      <h2 className={styles.title}>{lang('Open Positions')}</h2>
      {renderTotal()}
      {isPnlShown && (
        <PrivacyDust
          isHidden={Boolean(isSensitiveDataHidden)}
          isDisabled={isMotionDisabled}
          controller={controller}
          revision={`${appTheme}:${pnlTone}`}
          onClick={isSensitiveDataHidden ? handleTotalClick : undefined}
        >
          <div className={buildClassName(styles.change, styles[pnlTone ?? 'neutral'])}>
            {formatPerpsSignedMoney(totalPnl)}
            {pnlPercent !== undefined && ` · ${formatPercent(Math.abs(pnlPercent))}`}
          </div>
        </PrivacyDust>
      )}
    </section>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
    theme: global.settings.theme,
    animationLevel: global.settings.animationLevel,
  };
})(PositionListSummary));
