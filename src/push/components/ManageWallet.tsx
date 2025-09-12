import type { Wallet } from '@tonconnect/sdk';
import React, { memo, useMemo, useState } from '../../lib/teact/teact';

import { PUSH_CHAIN } from '../config';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { getTelegramApp } from '../../util/telegram';
import { getExplorerAddressUrl } from '../../util/url';
import { fetchAccountBalance } from '../util/check';
import { extractAndPurgeToken, getSearchParameter } from '../util/searchParams';
import { getWalletAddress } from '../util/tonConnect';
import { connectWallet, fetchConnectedAddress } from '../util/wallet';

import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useSyncEffect from '../../hooks/useSyncEffect';

import Header from './Header';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';

interface OwnProps {
  isActive: boolean;
  wallet?: Wallet;
  onConnectClick: () => Promise<void>;
  onDisconnectClick: NoneToVoidFunction;
}

const token = extractAndPurgeToken();
// Note: `URLSearchParams` decodes escape chars
const query = getSearchParameter('query');

function ConnectWallet({ isActive, wallet, onConnectClick, onDisconnectClick }: OwnProps) {
  const [connectedAddress, setConnectedAddress] = useState<string | undefined>();
  const [connectedWalletFriendly, setConnectedWalletFriendly] = useState<string>('');
  const [isLoading, markLoading, unmarkLoading] = useFlag(true);
  const [accountBalance, setAccountBalance] = useState<string>();

  const lang = useLang();

  useEffectOnce(() => {
    if (!token) return;

    void fetchConnectedAddress(token).then((response) => {
      setConnectedAddress(response.connectedAddress);
      unmarkLoading();
    });
  });

  useSyncEffect(() => {
    setConnectedWalletFriendly(wallet ? getWalletAddress(wallet) : '');
  }, [wallet]);

  useSyncEffect(() => {
    if (!token) return;

    if (wallet && connectedAddress !== wallet.account.address && !isLoading) {
      void connectWallet(wallet.account.address, token).then((response) => {
        setConnectedAddress(response.connectedAddress || undefined);
      });
    }
  }, [wallet, connectedAddress, isLoading]);

  const handleClick = useLastCallback(async () => {
    markLoading();
    if (!wallet) await onConnectClick();
    else {
      onDisconnectClick();
      await onConnectClick();
    }
    unmarkLoading();
  });

  const handleSecondaryClick = useLastCallback(() => {
    markLoading();

    const newQuery = query!.endsWith(' ') ? query!.slice(0, -1) : query + ' ';

    getTelegramApp()!.switchInlineQuery(newQuery);
    // It is assumed that the mini app will close
  });

  const walletUrl = useMemo(() => (
    wallet ? getExplorerAddressUrl(PUSH_CHAIN, getWalletAddress(wallet)) : undefined
  ), [wallet]);

  useSyncEffect(() => {
    if (wallet) {
      void fetchAccountBalanceFromWallet(wallet).then(setAccountBalance);
    }
  }, [wallet]);

  const handleDisconnectClick = useLastCallback((e) => {
    e.preventDefault();
    void onDisconnectClick();
  });

  return (
    <div className={buildClassName(commonStyles.container, commonStyles.container_centered)}>
      <Header
        walletUrl={walletUrl}
        connectedWalletFriendly={connectedWalletFriendly}
        accountBalance={accountBalance}
        onDisconnectClick={handleDisconnectClick}
      />

      <div className={commonStyles.content}>
        <h2 className={commonStyles.title}>{!wallet && lang('Connect Wallet')}</h2>
      </div>

      <div className={commonStyles.footer}>
        <UniversalButton isActive={isActive} onClick={handleClick} isPrimary={true}>
          {!wallet ? lang('Connect Wallet') : lang('Change Wallet')}
        </UniversalButton>
        <UniversalButton isActive={!!wallet} onClick={handleSecondaryClick} isPrimary={false}>
          {lang('Select NFT')}
        </UniversalButton>
      </div>
    </div>
  );
}

export default memo(ConnectWallet);

async function fetchAccountBalanceFromWallet(wallet: Wallet) {
  if (!wallet) return;

  const balanceBig = await fetchAccountBalance(getWalletAddress(wallet));

  return toDecimal(balanceBig, 9);
}
