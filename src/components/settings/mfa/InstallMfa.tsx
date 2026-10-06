import React, { memo, useMemo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { UserToken } from '../../../global/types';

import { ANIMATED_STICKER_BIG_SIZE_PX, MFA_INSTALL_FEE, TONCOIN } from '../../../config';
import { selectCurrentAccount, selectCurrentAccountTokens } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import { toDecimal } from '../../../util/decimals';
import { formatCurrency } from '../../../util/formatNumber';
import { ANIMATED_STICKERS_PATHS } from '../../ui/helpers/animatedAssets';

import useInterval from '../../../hooks/useInterval';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../ui/AnimatedIconWithPreview';
import Button from '../../ui/Button';

import settingsStyles from '../Settings.module.scss';
import styles from './Mfa.module.scss';

import benefitKeyImg from '../../../assets/settings/mfa/benefit_key.svg';
import benefitSecurityImg from '../../../assets/settings/mfa/benefit_security.svg';
import benefitTelegramImg from '../../../assets/settings/mfa/benefit_telegram.svg';

interface OwnProps {
  isActive: boolean;
  isSlideActive?: boolean;
}

interface StateProps {
  tokens?: UserToken[];
  isWalletSupported: boolean;

  installMfa?: {
    requestId?: string;
    user?: {
      id: string;
    };
  };
}

function InstallMfa({ isSlideActive, tokens, isWalletSupported, installMfa }: OwnProps & StateProps) {
  const lang = useLang();

  const { createInstallMfaRequest, updateInstallMfaRequest } = getActions();

  const hasInstallBalance = useMemo(() => {
    if (!tokens) return false;

    const ton = tokens.find((token) => token.slug === TONCOIN.slug);
    return !!ton && ton.amount >= MFA_INSTALL_FEE;
  }, [tokens]);

  const isAvailable = isWalletSupported && hasInstallBalance;

  useInterval(() => {
    if (isSlideActive && installMfa) updateInstallMfaRequest();
  }, 1000);

  const handleConnectTelegram = useLastCallback(() => {
    createInstallMfaRequest();
  });

  const isConfirming = installMfa && !installMfa.user;

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

      <div className={buildClassName(styles.title, styles.titleUninstalled)}>
        {lang('Confirm with')}{' '}
        <span>
          <i className={buildClassName('icon-telegram-filled', styles.icon)} aria-hidden />{' '}
          Telegram
        </span>
      </div>

      <div className={styles.benefitsContainer}>
        <div className={styles.block}>
          <img src={benefitSecurityImg} alt="" className={styles.benefitIcon} />

          <p className={styles.benefitText}>
            {lang('Add an extra layer of security for your wallet in TON network.')}
          </p>
        </div>

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
          className={buildClassName(styles.feeInfo, isWalletSupported && !hasInstallBalance && styles.feeInfoError)}
        >
          {lang('Connection Fee:')} {formatCurrency(toDecimal(MFA_INSTALL_FEE), TONCOIN.symbol)}
        </span>
        <Button
          onClick={handleConnectTelegram}
          isPrimary
          isDisabled={!isAvailable}
          isLoading={isConfirming}
          className={styles.button}
        >
          {!isWalletSupported
            ? lang('Unsupported Wallet Version')
            : isAvailable ? lang('Connect Telegram') : lang('Insufficient Balance')}
        </Button>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    tokens: selectCurrentAccountTokens(global),
    // MFA is a wallet extension, and only W5 wallets support extensions
    isWalletSupported: selectCurrentAccount(global)?.byChain.ton?.version === 'W5',
    installMfa: global.settings.installMfa,
  };
})(InstallMfa));
