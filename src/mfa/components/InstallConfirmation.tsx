import React, { memo, useEffect, useMemo } from '../../lib/teact/teact';

import type { ApiInstallRequest } from '../types';
import type { MfaWalletApp } from '../utils/startParam';

import buildClassName from '../../util/buildClassName';
import { shortenAddress } from '../../util/shortenAddress';
import { getTelegramApp } from '../../util/telegram';
import { confirmInstallRequest } from '../utils/installRequest';
import { getMfaWalletAppInfo } from '../utils/startParam';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import WalletAvatar from '../../components/ui/WalletAvatar';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';
import styles from './InstallConfirmation.module.scss';

import benefitTelegramImg from '../../assets/settings/mfa/benefit_telegram.svg';
import benefitTonImg from '../../assets/settings/mfa/benefit_ton.svg';

interface OwnProps {
  isActive: boolean;
  installRequest?: ApiInstallRequest;
  walletApp: MfaWalletApp;
  reqId?: string;
  onConfirm: () => void;
}

function InstallConfirmation({ installRequest, isActive, walletApp, reqId, onConfirm }: OwnProps) {
  const lang = useLang();
  const walletAppInfo = getMfaWalletAppInfo(walletApp);
  const appName = walletAppInfo.name;

  const [isLoading, setLoading, unsetLoading] = useFlag(true);

  useEffect(() => {
    if (installRequest) unsetLoading();
  }, [installRequest]);

  const onConfirmClicked = useLastCallback(() => {
    setLoading();

    confirmInstallRequest(reqId!, getTelegramApp()!.initData).then(() => {
      onConfirm();
    }).catch((err) => {
      alert(`ERROR: ${err}`);
    });
  });

  const { avatarUrl, firstName, lastName, username } = useMemo(() => {
    const app = getTelegramApp()!;
    const avatarUrl = app.initDataUnsafe.user?.photo_url;
    const firstName = app.initDataUnsafe.user?.first_name;
    const lastName = app.initDataUnsafe.user?.last_name;
    const username = app.initDataUnsafe.user?.username;

    return { avatarUrl, firstName, lastName, username };
  }, []);

  return (
    <div className={styles.container}>
      <div className={styles.avatars}>
        <WalletAvatar title="M" className={styles.avatar} />
        {avatarUrl ? (
          <img src={avatarUrl} alt="User Avatar" className={styles.avatar} />
        ) : <WalletAvatar title={firstName} className={styles.avatar} />}
      </div>

      <div className={buildClassName(commonStyles.title, styles.title)}>{lang('Confirm Connection')}</div>

      <div className={buildClassName(styles.block, styles.accounts)}>
        <div className={styles.account}>
          <span className={styles.accountDescription}>{lang('My Telegram Account')}</span>
          <div className={styles.accountCard}>
            {avatarUrl ? (
              <img src={avatarUrl} alt="User Avatar" className={styles.accountAvatar} />
            ) : <WalletAvatar title={firstName} className={styles.accountAvatar} />}

            <div className={styles.accountInfo}>
              <div className={styles.accountName}>
                {firstName}{' '}{lastName}
              </div>
              <div className={styles.accountAddress}>
                {username ? `@${username}` : lang('Without username')}
              </div>
            </div>
          </div>
        </div>

        <div className={styles.account}>
          <span className={styles.accountDescription}>{lang('My Wallet')}</span>
          <div className={styles.accountCard}>
            <WalletAvatar title="M" className={styles.accountAvatar} />

            <div className={styles.accountInfo}>
              <div className={styles.accountName}>
                {appName}
              </div>
              <div className={styles.accountAddress}>
                {shortenAddress(installRequest?.address || '')}
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className={styles.benefits}>
        <div className={buildClassName(styles.block, styles.benefitBlock)}>
          <img src={benefitTelegramImg} alt="" className={styles.benefitIcon} />

          <div className={styles.benefitText}>
            {lang('We’ll ask you to confirm actions with Telegram after entering your passcode in %app_name%.', {
              app_name: appName,
            })}
          </div>
        </div>

        <div className={buildClassName(styles.block, styles.benefitBlock)}>
          <img src={benefitTonImg} alt="" className={styles.benefitIcon} />

          <div className={styles.benefitText}>
            {lang('2FA applies only to actions involving TON assets.')}
          </div>
        </div>
      </div>

      <UniversalButton
        isPrimary
        isActive={isActive}
        isLoading={isLoading}
        onClick={onConfirmClicked}
      >
        {lang('Confirm')}
      </UniversalButton>
    </div>
  );
}

export default memo(InstallConfirmation);
