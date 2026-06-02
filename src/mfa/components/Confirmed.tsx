import React, { memo } from '../../lib/teact/teact';

import type { MfaWalletApp } from '../utils/startParam';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../config';
import buildClassName from '../../util/buildClassName';
import { getTelegramApp } from '../../util/telegram';
import { ANIMATED_STICKERS_PATHS } from '../../components/ui/helpers/animatedAssets';
import { getMfaWalletAppInfo } from '../utils/startParam';

import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';
import styles from './Confirmed.module.scss';

interface OwnProps {
  isActive: boolean;

  isTransaction?: boolean;
  walletApp: MfaWalletApp;
}

function Confirmed({ isActive, isTransaction, walletApp }: OwnProps) {
  const lang = useLang();
  const walletAppInfo = getMfaWalletAppInfo(walletApp);

  const onClick = () => {
    const telegramApp = getTelegramApp();
    if (telegramApp) {
      telegramApp.openLink(walletAppInfo.deeplink);
      return;
    }

    window.location.href = walletAppInfo.deeplink;
  };

  return (
    <div className={buildClassName(commonStyles.container, styles.container)}>
      <AnimatedIconWithPreview
        className={commonStyles.sticker}
        play
        noLoop={false}
        nonInteractive
        size={ANIMATED_STICKER_BIG_SIZE_PX}
        tgsUrl={ANIMATED_STICKERS_PATHS.happy}
        previewUrl={ANIMATED_STICKERS_PATHS.happyPreview}
      />

      <div className={buildClassName(commonStyles.title, styles.title)}>
        {isTransaction ? lang('Transaction sent!') : lang('Almost Ready!')}
      </div>

      {!isTransaction && (
        <div className={styles.description}>
          <span className={commonStyles.strong}>{lang('Your wallet is now connected to your Telegram account.')}</span>
          <span>{lang('Return to the app to pay fee and complete the final confirmation.')}</span>
        </div>
      )}

      <UniversalButton
        isPrimary
        isActive={isActive}
        onClick={onClick}
      >
        {`Back to ${walletAppInfo.name}`}
      </UniversalButton>
    </div>
  );
}

export default memo(Confirmed);
