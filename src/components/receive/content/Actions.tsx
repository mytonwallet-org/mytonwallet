import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiChain, ApiCountryCode } from '../../../api/types';

import { selectIsCurrentAccountViewMode } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { getChainConfig } from '../../../util/chain';
import { getNativeToken } from '../../../util/tokens';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import styles from './Actions.module.scss';

interface OwnProps {
  chain: ApiChain;
  isLedger?: boolean;
  className?: string;
  onClose?: NoneToVoidFunction;
}

interface StateProps {
  isTestnet?: boolean;
  isSwapDisabled?: boolean;
  isOnRampDisabled?: boolean;
  isViewMode?: boolean;
  countryCode?: ApiCountryCode;
}

function Actions({
  chain,
  className,
  isTestnet,
  isLedger,
  isSwapDisabled,
  isOnRampDisabled,
  isViewMode,
  countryCode,
  onClose,
}: OwnProps & StateProps) {
  const {
    startSwap,
    openOnRampWidgetModal,
    openInvoiceModal,
    closeReceiveModal,
  } = getActions();

  const lang = useLang();

  const { canBuyWithCardInRussia, isOnRampSupported, formatTransferUrl, buySwap } = getChainConfig(chain);
  const canBuyWithCard = isOnRampSupported && (canBuyWithCardInRussia || countryCode !== 'RU');
  const isSwapAllowed = !isViewMode && !isTestnet && !isLedger && !isSwapDisabled && !!buySwap;
  const isOnRampAllowed = !isViewMode && !isTestnet && !isOnRampDisabled && canBuyWithCard;
  const isDepositLinkSupported = !!formatTransferUrl;
  const shouldRender = Boolean(isSwapAllowed || isOnRampAllowed || isDepositLinkSupported);

  const handleBuyFiat = useLastCallback(() => {
    openOnRampWidgetModal({ chain });
    onClose?.();
  });

  const handleSwapClick = useLastCallback(() => {
    startSwap({
      tokenInSlug: buySwap!.tokenInSlug,
      tokenOutSlug: getNativeToken(chain).slug,
      amountIn: buySwap!.amountIn,
    });
    onClose?.();
  });

  const handleReceiveClick = useLastCallback(() => {
    closeReceiveModal();
    openInvoiceModal({ tokenSlug: getNativeToken(chain).slug });
    onClose?.();
  });

  const contentClassName = buildClassName(
    styles.actionButtons,
    className,
  );

  if (!shouldRender) {
    return undefined;
  }

  return (
    <div className={contentClassName}>
      {isOnRampAllowed && (
        <div
          className={buildClassName(styles.actionButton, !canBuyWithCard && styles.disabled)}
          onClick={canBuyWithCard ? handleBuyFiat : undefined}
        >
          <i className={buildClassName(styles.actionIcon, 'icon-card')} aria-hidden />
          {lang('Buy with Card')}
          <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
        </div>
      )}
      {isSwapAllowed && (
        <div className={styles.actionButton} onClick={handleSwapClick}>
          <i className={buildClassName(styles.actionIcon, 'icon-crypto')} aria-hidden />
          {lang('Buy with Crypto')}
          <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
        </div>
      )}
      {isDepositLinkSupported && (
        <div className={styles.actionButton} onClick={handleReceiveClick}>
          <i className={buildClassName(styles.actionIcon, 'icon-link')} aria-hidden />
          {lang('Create Deposit Link')}
          <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
        </div>
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isSwapDisabled,
    isOnRampDisabled,
    countryCode,
  } = global.restrictions;

  return {
    isTestnet: global.settings.isTestnet,
    isSwapDisabled,
    isOnRampDisabled,
    isViewMode: selectIsCurrentAccountViewMode(global),
    countryCode,
  };
})(Actions));
