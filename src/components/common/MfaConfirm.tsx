import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import { MFA_BOT_URL } from '../../config';
import { selectCurrentAccount, selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { buildMfaStartParam } from '../../util/mfa';
import { openSite } from '../explore/helpers/utils';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';
import WalletAvatar from '../ui/WalletAvatar';

import modalStyles from '../ui/Modal.module.scss';
import avatarStyles from '../ui/WalletAvatar.module.scss';
import styles from './MfaConfirm.module.scss';

interface OwnProps {
  onClose: () => void;
  children?: TeactNode;

  mfaRequestHash?: string;
}

interface StateProps {
  accountId?: string;
  accountTitle?: string;

  mfa: {
    user?: {
      name: string;
      username?: string;
      avatarUrl?: string;
    };
  };
}

function ConfirmMfa({
  children,
  accountId,
  accountTitle,
  mfaRequestHash,
  mfa,
  onClose,
}: OwnProps & StateProps) {
  const lang = useLang();
  const telegramAccountName = mfa.user?.name ?? lang('My Telegram Account');

  const handleSubmit = () => {
    const url = new URL(MFA_BOT_URL);
    url.searchParams.set('startapp', buildMfaStartParam(mfaRequestHash!));

    openSite(url.toString(), true);
  };

  return (
    <div className={modalStyles.transitionContent}>
      <div className={styles.avatars}>
        <WalletAvatar
          accountId={accountId}
          title={accountTitle}
          className={styles.avatar}
        />
        {mfa.user?.avatarUrl ? (
          <img
            src={mfa.user.avatarUrl}
            alt="Avatar"
            className={buildClassName(avatarStyles.avatar, styles.avatar)}
          />
        ) : (
          <WalletAvatar
            title={telegramAccountName}
            className={styles.avatar}
          />
        )}
      </div>

      <div className={buildClassName(styles.title)}>
        {lang('Confirm with')}{' '}
        <span>
          <i className={buildClassName('icon-telegram-filled', styles.icon)} aria-hidden />{' '}
          Telegram
        </span>
      </div>

      {children}

      <div className={styles.infoBlock}>
        <i className={buildClassName('icon-key', styles.infoIcon, styles.icon)} aria-hidden />

        <p className={styles.infoText}>
          {lang('An extra security layer requires confirming actions in Telegram after signing.')}
        </p>
      </div>

      <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsInsideContentWithScroll)}>
        <Button className={modalStyles.button} onClick={onClose}>
          {lang('Cancel')}
        </Button>
        <Button
          isPrimary
          className={modalStyles.button}
          onClick={handleSubmit}
        >
          {lang('Confirm')}
        </Button>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global) => {
  const account = selectCurrentAccount(global);
  const accountTitle = account?.title;

  return {
    accountTitle,
    accountId: selectCurrentAccountId(global),
    mfa: account?.byChain.ton?.mfa,
  };
})(ConfirmMfa));
