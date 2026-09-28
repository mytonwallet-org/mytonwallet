import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiChain } from '../../api/types';
import type { Account } from '../../global/types';

import { DEFAULT_CHAIN } from '../../config';
import {
  selectCurrentAccountId,
  selectCurrentToncoinBalance,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatNumber } from '../../util/formatNumber';

import useLang from '../../hooks/useLang';
import usePillIcons from './hooks/usePillIcons';

import Image from '../ui/Image';
import SensitiveData from '../ui/SensitiveData';
import WalletAvatar from '../ui/WalletAvatar';
import DappHostWarning from './DappHostWarning';

import styles from './Dapp.module.scss';

const DAPP_LOGO_CLASS_NAME = buildClassName(styles.dappLogo, styles.dappLogo_round);
const DAPP_LOGO_FALLBACK = (
  <i
    className={buildClassName(DAPP_LOGO_CLASS_NAME, styles.dappLogo_icon, styles.dappIcon, 'icon-laptop')}
    aria-hidden
  />
);

interface OwnProps {
  chain?: ApiChain;
  dapp?: StoredDappConnection;
  customTokenBalance?: bigint;
  customTokenSymbol?: string;
  customTokenDecimals?: number;
}

interface StateProps {
  toncoinBalance: bigint;
  currentAccountId: string;
  accounts?: Record<string, Account>;
  isSensitiveDataHidden?: true;
}

function DappInfoWithAccount({
  chain,
  dapp,
  toncoinBalance,
  currentAccountId,
  accounts,
  isSensitiveDataHidden,
  customTokenBalance,
  customTokenSymbol,
  customTokenDecimals,
}: OwnProps & StateProps) {
  const lang = useLang();

  const {
    headerRef, accountPillRef, dappPillRef, linkRef, walletNameRef, dappNameRef, dappHostRef,
  } = usePillIcons();

  // Use custom token display if provided, otherwise use TON balance
  const displayBalance = customTokenBalance !== undefined ? customTokenBalance : toncoinBalance;
  const displaySymbol = customTokenSymbol || getChainConfig(chain || DEFAULT_CHAIN).nativeToken.symbol;
  const displayDecimals = customTokenDecimals !== undefined
    ? customTokenDecimals
    : getChainConfig(chain || DEFAULT_CHAIN).nativeToken.decimals;

  const accountTitle = accounts?.[currentAccountId]?.title;
  const [wholeBalance, fractionBalance] = formatNumber(toDecimal(displayBalance, displayDecimals)).split('.');

  const { name: dappName, iconUrl: dappIconUrl, url: dappUrl, urlTrustStatus } = dapp || {};
  const dappHost = useMemo(() => dappUrl ? new URL(dappUrl).host : undefined, [dappUrl]);

  return (
    <div ref={headerRef} className={styles.requestHeader}>
      <div ref={accountPillRef} className={styles.headerPill}>
        <WalletAvatar
          accountId={currentAccountId}
          title={accountTitle}
          className={buildClassName(styles.headerPillAvatar, styles.headerPillLeadingIcon)}
        />
        <div className={styles.headerPillText}>
          <SensitiveData
            isActive={isSensitiveDataHidden}
            rows={2}
            cellSize={8}
            min={5}
            max={10}
            seed={currentAccountId}
            className={styles.headerPillSensitiveData}
            contentClassName={buildClassName(styles.headerPillTitle, styles.headerPillSensitiveDataContent)}
          >
            <div className={styles.headerPillBalance}>
              <span>{wholeBalance}</span>
              <span className={styles.headerPillTitleSecondary}>
                {fractionBalance && `.${fractionBalance}`}&nbsp;{displaySymbol}
              </span>
            </div>
          </SensitiveData>
          <div className={styles.headerPillSubtitle}>
            <span
              ref={walletNameRef}
              className={buildClassName(styles.headerPillSubtitleText, styles.headerPillWalletName)}
            >
              {accountTitle}
            </span>
          </div>
        </div>
      </div>

      <i ref={linkRef} className={styles.headerPillLink} aria-hidden />

      <div ref={dappPillRef} className={buildClassName(styles.headerPill, styles.headerPill_dapp)}>
        <div className={buildClassName(styles.headerPillText, styles.headerPillText_dapp)}>
          <span ref={dappNameRef} className={styles.headerPillTitle}>{dappName}</span>
          <span className={styles.headerPillSubtitle}>
            <span ref={dappHostRef} className={styles.headerPillSubtitleText}>{dappHost}</span>
            {urlTrustStatus !== 'verified' && (
              <DappHostWarning
                urlTrustStatus={urlTrustStatus}
                iconClassName={styles.headerPillWarningIcon}
                isCompact
              />
            )}
          </span>
        </div>
        <Image
          url={dappIconUrl}
          alt={dappName || lang('Logo')}
          forceLoaded
          className={buildClassName(DAPP_LOGO_CLASS_NAME, styles.headerPillTrailingIcon)}
          imageClassName={DAPP_LOGO_CLASS_NAME}
          fallback={DAPP_LOGO_FALLBACK}
        />
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accounts = selectNetworkAccounts(global);

  return {
    toncoinBalance: selectCurrentToncoinBalance(global),
    currentAccountId: selectCurrentAccountId(global)!,
    accounts,
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(DappInfoWithAccount));
