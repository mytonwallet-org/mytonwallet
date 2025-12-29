import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiChain, ApiCountryCode } from '../../../api/types';

import buildClassName from '../../../util/buildClassName';
import { getChainConfig } from '../../../util/chain';
import { getNativeToken } from '../../../util/tokens';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import styles from './Actions.module.scss';

interface OwnProps {
  chain: ApiChain;
  isStatic?: boolean;
  isLedger?: boolean;
  className?: string;
  onClose?: NoneToVoidFunction;
}

interface StateProps {
  isTestnet?: boolean;
  isSwapDisabled?: boolean;
  isOnRampDisabled?: boolean;
  countryCode?: ApiCountryCode;
}

function Actions({
  chain,
  className,
  isStatic,
  isTestnet,
  isLedger,
  isSwapDisabled,
  isOnRampDisabled,
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

  const { canBuyWithCardInRussia, formatTransferUrl } = getChainConfig(chain);
  const canBuyWithCard = canBuyWithCardInRussia || countryCode !== 'RU';
  const isSwapAllowed = !isTestnet && !isLedger && !isSwapDisabled;
  // TRX purchase is not possible via the Dreamwalkers service (Russian), however in static mode we show the buy button
  const isOnRampAllowed = !isTestnet && !isOnRampDisabled && (canBuyWithCard || isStatic);
  const isDepositLinkSupported = !!formatTransferUrl;
  const shouldRender = Boolean(isSwapAllowed || isOnRampAllowed || isStatic);

  const handleBuyFiat = useLastCallback(() => {
    openOnRampWidgetModal({ chain });
    onClose?.();
  });

  const handleSwapClick = useLastCallback(() => {
    const { tokenInSlug, amountIn } = getChainConfig(chain).buySwap;

    startSwap({
      tokenInSlug,
      tokenOutSlug: getNativeToken(chain).slug,
      amountIn,
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
    isStatic && styles.actionButtonStatic,
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
      {(isStatic || isDepositLinkSupported) && (
        <div
          className={buildClassName(styles.actionButton, !isDepositLinkSupported && styles.disabled)}
          onClick={isDepositLinkSupported ? handleReceiveClick : undefined}
        >
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
    countryCode,
  };
})(Actions));
