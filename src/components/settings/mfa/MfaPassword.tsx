import React, { memo, useEffect, useState } from '../../../lib/teact/teact';
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
    failedAttemptCount?: number;
  };

  mfa?: {
    user?: {
      name: string;
      username?: string;
      avatarUrl?: string;
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

  // How many install attempts had failed when the user last pressed Connect. The install is still running
  // while `failedAttemptCount` has not grown. The error text can't show this: the same error twice in a row
  // looks unchanged.
  const [failedAttemptsAtSubmit, setFailedAttemptsAtSubmit] = useState<number>();
  const failedAttemptCount = installMfa?.failedAttemptCount ?? 0;

  // After a successful install the request is cleared, but the screen keeps the install mode and the loader
  // until it switches to the success screen
  const isInstallSubmitted = failedAttemptsAtSubmit !== undefined;
  const isInstall = Boolean(installMfa) || isInstallSubmitted;
  const isInstalling = isInstallSubmitted && (!installMfa || failedAttemptCount === failedAttemptsAtSubmit);
  const telegramUser = installMfa?.user ?? mfa?.user;
  const telegramAccountName = telegramUser?.name ?? lang('My Telegram Account');
  const telegramAccountUsername = telegramUser?.username && `@${telegramUser.username}`;

  // The install has succeeded once the account has `mfa` and the action has cleared `installMfa`. Waiting for
  // the clearing matters: the success screen prepares the `Mfa` screen in advance, and `Mfa` reopens this one
  // while the request still exists.
  useEffect(() => {
    if (isInstallSubmitted && mfa && !installMfa) openMfaInstalled();
  }, [isInstallSubmitted, mfa, installMfa, openMfaInstalled]);

  const handleAuthorize = useLastCallback((enclaveToken: string) => {
    if (isInstall) {
      setFailedAttemptsAtSubmit(failedAttemptCount);
      submitInstallMfa({ enclaveToken });
    } else {
      submitRemoveMfa({ enclaveToken });
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
          // After a correct passcode `PasswordForm` ignores further input until it is shown again. A failed
          // install changes the `key`, which creates a new form, so the user can retry. With biometrics, the new
          // form asks for them right away.
          key={failedAttemptCount}
          isActive={isActive}
          isLoading={isInstalling}
          error={error}
          submitLabel={isInstall ? lang('Connect') : lang('Disconnect')}
          noAutoConfirm
          // Installing signs the extension and then derives the backend auth token from the private
          // key until it is cached, so the first install on an account reads the secret twice
          extraAuthUsages={isInstall ? 1 : 0}
          onAuthorize={handleAuthorize}
          onCancel={onBack}
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
              <WalletAvatar
                title={telegramUser?.name}
                imageUrl={telegramUser?.avatarUrl}
                className={styles.avatar}
              />
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
