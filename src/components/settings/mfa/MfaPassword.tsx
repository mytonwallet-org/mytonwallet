import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { selectCurrentAccount, selectCurrentAccountId } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import Banner from '../../common/Banner';
import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';
import PasswordForm from '../../ui/PasswordForm';
import WalletAvatar from '../../ui/WalletAvatar';

import avatarStyles from '../../../components/ui/WalletAvatar.module.scss';
import settingsStyles from '../Settings.module.scss';
import styles from './Mfa.module.scss';

interface OwnProps {
  isActive: boolean;
  isInsideModal?: boolean;

  onBackClick: () => void;
  openMfaInstalled: () => void;
  openMfa: () => void;
}

interface StateProps {
  error?: string;
  accountId?: string;
  accountTitle?: string;

  installMfa?: {
    requestId: string;
    user?: {
      id: string;
      name: string;
      username?: string;
      avatarUrl?: string;
    };
  };

  mfa?: {
    user?: {
      name: string;
      username?: string;
    };
  };
}

function MfaPassword({
  isActive,
  isInsideModal,
  error,
  accountId,
  accountTitle,
  installMfa,
  mfa,
  onBackClick,
  openMfaInstalled,
  openMfa,
}: OwnProps & StateProps) {
  const lang = useLang();

  const { clearInstallMfaError, clearMfaRequests, submitInstallMfa, submitRemoveMfa } = getActions();

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const isInstall = !!installMfa;
  const telegramUser = installMfa?.user ?? mfa?.user;
  const telegramAccountName = telegramUser?.name ?? lang('My Telegram Account');
  const telegramAccountUsername = telegramUser?.username && `@${telegramUser.username}`;

  const onSubmit = useLastCallback((password?: string) => {
    if (isInstall) {
      submitInstallMfa({ password });
      openMfaInstalled();
    } else {
      submitRemoveMfa({ password });
      openMfa();
    };
  });

  const onBack = useLastCallback(() => {
    clearMfaRequests();
    onBackClick();
  });

  return (
    <div className={settingsStyles.slide}>
      {isInsideModal ? (
        <ModalHeader
          onBackButtonClick={onBack}
          className={settingsStyles.modalHeader}
          withNotch={isScrolled}
        />
      ) : (
        <div className={settingsStyles.header}>
          <Button isSimple isText onClick={onBack} className={settingsStyles.headerBack}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
        </div>
      )}

      <div
        className={buildClassName(settingsStyles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        <PasswordForm
          isActive={isActive}
          error={error}
          submitLabel={isInstall ? lang('Connect') : lang('Disconnect')}
          noAutoConfirm
          onSubmit={onSubmit}
          onCancel={onBackClick}
          onUpdate={clearInstallMfaError}
          noAnimatedIcon
        >
          {isInstall && (
            <div className={styles.avatars}>
              <WalletAvatar
                accountId={accountId}
                title={accountTitle}
                className={styles.avatar}
              />
              {installMfa.user?.avatarUrl ? (
                <img
                  src={installMfa.user.avatarUrl}
                  alt="Account"
                  className={buildClassName(styles.avatar, avatarStyles.avatar)}
                />
              ) : (
                <WalletAvatar
                  title={installMfa.user?.name}
                  className={styles.avatar}
                />
              )}
            </div>
          )}
          <div className={styles.title}>{isInstall ? lang('Confirm Connection') : lang('Confirm Disconnection')}</div>
          <Banner
            icon="icon-telegram-filled"
            className={styles.banner}
            text={telegramAccountName}
            secondText={telegramAccountUsername}
          />
        </PasswordForm>
      </div>
    </div>

  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const account = selectCurrentAccount(global);

  const accountTitle = account?.title;
  const { installMfa } = global.settings;

  return {
    error: installMfa?.error,
    accountId,
    accountTitle,
    installMfa,
    mfa: account?.byChain.ton?.mfa,
  };
})(MfaPassword));
