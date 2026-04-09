import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiTonWalletVersion } from '../../../api/chains/ton/types';
import type { ApiChain, ApiWalletByChain } from '../../../api/types';
import type { Wallet } from './SettingsWalletVariants';

import buildClassName from '../../../util/buildClassName';
import { shortenAddress } from '../../../util/shortenAddress';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Button from '../../ui/Button';
import WalletVariantListItem from './WalletVariantListItem';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  isInsideModal?: boolean;
  currentVersion?: ApiTonWalletVersion;
  wallets: Wallet[];
  onBackClick: NoneToVoidFunction;
}

function SettingsWalletVersions({
  isActive,
  isInsideModal,
  currentVersion,
  wallets,
  onBackClick,
}: OwnProps) {
  const { closeSettings, importAccountByVersion } = getActions();
  const lang = useLang();

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const handleWalletVersionClick = useLastCallback((
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    arg: {
      chain: ApiChain;
      isTestnetSubwalletId?: boolean;
      newWallet: Omit<ApiWalletByChain[ApiChain], 'index'>;
      isReplace: boolean;
    },
  ) => {
    if (!('version' in arg.newWallet)) return;

    const { version } = arg.newWallet as { version: ApiTonWalletVersion };

    closeSettings();
    importAccountByVersion({
      version,
      isTestnetSubwalletId: arg.isTestnetSubwalletId,
    });
  });

  const walletsWithCbArg = useMemo(() => {
    return wallets.map((w) => ({
      ...w,
      clickArg: {
        chain: 'ton' as ApiChain,
        newWallet: {
          address: w.address,
          version: w.version,
        } as Omit<ApiWalletByChain['ton'], 'index'>,
        isTestnetSubwalletId: w.isTestnetSubwalletId,
        isReplace: true,
      },
    }));
  }, [wallets]);

  return (
    <div className={styles.slide}>
      <div className={buildClassName(
        isInsideModal ? modalStyles.header : styles.header,
        'with-notch-on-scroll',
        isScrolled && 'is-scrolled',
        isInsideModal && styles.modalHeader,
      )}
      >
        <Button
          isSimple
          isText
          onClick={onBackClick}
          className={isInsideModal ? modalStyles.header_back : styles.headerBack}
        >
          <i
            className={buildClassName(
              isInsideModal ? modalStyles.header_backIcon : styles.iconChevron,
              'icon-chevron-left',
            )}
            aria-hidden
          />
          {!isInsideModal && <span>{lang('Back')}</span>}
        </Button>
        <span className={isInsideModal ? modalStyles.title : styles.headerTitle}>
          {lang('Wallet Versions')}
        </span>
      </div>

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        <div className={styles.blockWalletVersionText}>
          <span>{lang('$current_wallet_version', { version: <strong>{currentVersion}</strong> })}</span>
          <span>{lang('You have tokens on other versions of your wallet. You can import them from here.')}</span>
        </div>
        <div className={styles.block}>
          {walletsWithCbArg.map((w) => {
            const displayVersion = w.version === 'W5' && w.isTestnetSubwalletId !== undefined
              ? `${w.version} (${w.isTestnetSubwalletId ? 'Testnet' : 'Mainnet'} Subwallet ID)`
              : w.version;
            const address = w.address ?? '';

            return (
              <WalletVariantListItem
                key={address}
                title={displayVersion}
                subtitle={shortenAddress(address) ?? ''}
                tokens={w.tokens.join(', ')}
                totalBalance={w.totalBalance ?? ''}
                onClick={handleWalletVersionClick}
                clickArg={w.clickArg}
              />
            );
          })}
        </div>

        <div className={styles.blockWalletVersionReadMore}>
          {lang('$read_more_about_wallet_version', {
            link: (
              <a href="https://docs.ton.org/participate/wallets/contracts" target="_blank" rel="noreferrer">
                ton.org
              </a>
            ),
          })}
        </div>
      </div>
    </div>
  );
}

export default memo(SettingsWalletVersions);
