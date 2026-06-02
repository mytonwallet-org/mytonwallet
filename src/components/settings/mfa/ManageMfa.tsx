import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../../config';
import { selectCurrentAccount } from '../../../global/selectors';
import { getHasInMemoryPassword, getInMemoryPassword } from '../../../util/authApi/inMemoryPasswordStore';
import buildClassName from '../../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useInterval from '../../../hooks/useInterval';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';
import WalletAvatar from '../../ui/WalletAvatar';

import avatarStyles from '../../../components/ui/WalletAvatar.module.scss';
import settingsStyles from '../Settings.module.scss';
import styles from './Mfa.module.scss';

import benefitKeyImg from '../../../assets/settings/mfa/benefit_key.svg';
import benefitTelegramImg from '../../../assets/settings/mfa/benefit_telegram.svg';

interface OwnProps {
  isSlideActive?: boolean;
  openMfaPassword: () => void;
}

interface StateProps {
  removeMfa?: {
    requestId: string;
  };
  mfa: {
    user?: {
      name: string;
      username?: string;
      avatarUrl?: string;
    };
  };
}

function ManageMfa({
  isSlideActive,
  removeMfa,
  mfa,
  openMfaPassword,
}: OwnProps & StateProps) {
  const lang = useLang();

  const { submitRemoveMfa, updateRemoveMfaRequest } = getActions();

  const isConfirming = !!removeMfa;
  const telegramAccountName = mfa.user?.name ?? lang('My Telegram Account');
  const telegramAccountUsername = mfa.user?.username ? `@${mfa.user.username}` : lang('Without username');

  const onClick = useLastCallback(async () => {
    if (getHasInMemoryPassword()) {
      submitRemoveMfa({ password: await getInMemoryPassword() });
    } else {
      openMfaPassword();
    }
  });

  useInterval(() => {
    if (isSlideActive && removeMfa) updateRemoveMfaRequest();
  }, 1000);

  return (
    <>
      <AnimatedIconWithPreview
        tgsUrl={isConfirming ? ANIMATED_STICKERS_PATHS.wait : ANIMATED_STICKERS_PATHS.snitch}
        previewUrl={isConfirming ? ANIMATED_STICKERS_PATHS.waitPreview : ANIMATED_STICKERS_PATHS.snitchPreview}
        play={isSlideActive}
        size={ANIMATED_STICKER_BIG_SIZE_PX}
        nonInteractive
        noLoop={false}
        className={settingsStyles.sticker}
      />

      <div className={styles.title}>
        {lang('Confirm with')}{' '}
        <span>
          <i className={buildClassName('icon-telegram-filled', styles.icon)} aria-hidden />{' '}
          Telegram
        </span>
      </div>

      <div className={styles.account}>
        <div className={styles.accountDescription}>
          {lang('My Telegram Account')}
        </div>
        <div className={buildClassName(styles.block, styles.accountBlock)}>
          {mfa.user?.avatarUrl ? (
            <img
              src={mfa.user.avatarUrl}
              alt="Avatar"
              className={avatarStyles.avatar}
            />
          ) : (
            <WalletAvatar title={telegramAccountName.slice(0, 2)} />
          )}

          <div className={styles.accountInfo}>
            <div className={styles.accountName}>{telegramAccountName}</div>

            {telegramAccountUsername && <div className={styles.accountUsername}>{telegramAccountUsername}</div>}
          </div>
        </div>
      </div>

      <div className={styles.benefitsContainer}>
        <div className={styles.block}>
          <img src={benefitTelegramImg} alt="" className={styles.benefitIcon} />

          <p className={styles.benefitText}>
            {lang('Sign transfers and important actions with your passcode, then confirm them in Telegram.')}
          </p>
        </div>

        <div className={styles.block}>
          <img src={benefitKeyImg} alt="" className={styles.benefitIcon} />

          <p className={styles.benefitText}>
            {lang('This helps protect your funds even if your recovery phrase or keys are compromised.')}
          </p>
        </div>
      </div>

      <div className={styles.actions}>
        <span
          className={styles.feeInfo}
        >
          {lang('Connection Fee:')} 0.15 TON
        </span>
        <Button
          isDestructive
          isLoading={isConfirming}
          className={styles.button}
          onClick={onClick}
        >
          {lang('Unlink Account')}
        </Button>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const account = selectCurrentAccount(global);
  const { removeMfa } = global.settings;

  return {
    removeMfa,
    mfa: account!.byChain.ton!.mfa!,
  };
})(ManageMfa));
