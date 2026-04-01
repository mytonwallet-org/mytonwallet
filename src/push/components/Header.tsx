import React, { memo } from '../../lib/teact/teact';

import type { TokenSymbol } from '../types';

import buildClassName from '../../util/buildClassName';
import { formatCurrency } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';

import useLang from '../../hooks/useLang';

import AnimatedCounter from '../../components/ui/AnimatedCounter';
import Transition from '../../components/ui/Transition';

import styles from './Header.module.scss';

const PLACEHOLDER = '···';
const ADDRESS_LENGTH = 6;

interface OwnProps {
  walletUrl?: string;
  accountAddress?: string;
  accountBalance?: string;
  onDisconnectClick: (e: any) => void;
  symbol?: TokenSymbol;
}

function Header({ walletUrl, accountBalance, accountAddress, onDisconnectClick, symbol }: OwnProps) {
  const lang = useLang();

  return (
    <div className={styles.header}>
      <div className={buildClassName(styles.wallet, !walletUrl && styles.wallet_empty)}>
        <a href={walletUrl} target="_blank" rel="noreferrer" className={styles.walletAvatar}>
          <i />
        </a>
        <div className={styles.walletInfo}>
          <Transition name="fade" activeKey={accountBalance ? 1 : 0} className={styles.walletBalance}>
            {accountBalance ? (
              <a href={walletUrl} target="_blank" rel="noreferrer" className={styles.walletBalanceLink}>
                {accountAddress && (
                  `${shortenAddress(accountAddress, 0, ADDRESS_LENGTH)} · `
                )}
                <AnimatedCounter text={formatCurrency(accountBalance, symbol ?? 'TON')} />
              </a>
            ) : (
              PLACEHOLDER
            )}
          </Transition>
          <a href="" className={styles.walletDisconnectLink} onClick={onDisconnectClick}>
            {lang('Disconnect')}
          </a>
        </div>
      </div>

      <a href="https://t.me/push?start=1" className={styles.helpButton}><i /></a>
    </div>
  );
}

export default memo(Header);
