import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsOperation } from '../../api/types';

import { selectPerpsBannerOperation, selectPerpsMarketAsset } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getOperationBannerTitle, getOperationMessage } from './helpers/formatPerps';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import styles from './Futures.module.scss';

interface OwnProps {
  className?: string;
}

interface StateProps {
  operation?: ApiPerpsOperation;
  symbol?: string;
}

function OperationBanner({ className, operation, symbol }: OwnProps & StateProps) {
  const { openPerpsOperation, hidePerpsOperationBanner } = getActions();

  const lang = useLang();

  const handleClick = useLastCallback(() => {
    openPerpsOperation({ operationId: operation!.id });
  });

  const handleHideClick = useLastCallback(() => {
    hidePerpsOperationBanner({ operationId: operation!.id });
  });

  if (!operation) return undefined;

  return (
    <div className={buildClassName(styles.card, styles.operationBanner, className)}>
      <button type="button" className={styles.operationBannerText} onClick={handleClick}>
        <span className={styles.operationBannerTitle}>{getOperationBannerTitle(lang, operation, symbol)}</span>
        <span className={styles.operationBannerMessage}>{getOperationMessage(lang, operation)}</span>
      </button>
      <button
        type="button"
        className={styles.operationBannerHide}
        aria-label={lang('Hide')}
        onClick={handleHideClick}
      >
        <i className="icon-close" aria-hidden />
      </button>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const operation = selectPerpsBannerOperation(global);

  return {
    operation,
    symbol: operation && selectPerpsMarketAsset(global, operation.assetId)?.symbol,
  };
})(OperationBanner));
