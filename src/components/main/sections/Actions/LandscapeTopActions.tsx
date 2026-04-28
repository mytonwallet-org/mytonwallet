import React, { memo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { Account, Theme } from '../../../../global/types';
import type { StakingStateStatus } from '../../../../util/staking';

import { ANIMATED_STICKER_ICON_PX } from '../../../../config';
import {
  selectAccountStakingState,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectIsCurrentAccountViewMode,
  selectIsOffRampAllowed,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
} from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import { CHAIN_ORDER } from '../../../../util/chain';
import { vibrate } from '../../../../util/haptics';
import { getStakingStateStatus } from '../../../../util/staking';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import { STAKING_TAB_TEXT_VARIANTS } from './helpers/stakingLabels';

import useAppTheme from '../../../../hooks/useAppTheme';
import useFlag from '../../../../hooks/useFlag';
import useHorizontalScroll from '../../../../hooks/useHorizontalScroll';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './LandscapeTopActions.module.scss';

const ANIMATED_STICKER_SPEED = 2;

interface ActionButtonProps {
  label: string;
  className?: string;
  tgsUrl: string;
  previewUrl: string;
  accentColor?: string;
  onClick: NoneToVoidFunction;
}

interface StateProps {
  isViewMode: boolean;
  isSwapDisabled?: boolean;
  isStakingDisabled?: boolean;
  isOnRampDisabled?: boolean;
  isOffRampDisabled?: boolean;
  accountByChain?: Account['byChain'];
  stakingStatus: StakingStateStatus;
  theme: Theme;
  accentColorIndex?: number;
}

function LandscapeTopActions({
  isViewMode,
  isSwapDisabled,
  isStakingDisabled,
  isOnRampDisabled,
  isOffRampDisabled,
  accountByChain,
  stakingStatus,
  theme,
  accentColorIndex,
}: StateProps) {
  const {
    startTransfer,
    startSwap,
    openReceiveModal,
    openOnRampWidgetModal,
    openOffRampWidgetModal,
    openStakingInfoOrStart,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];
  const accentColor = accentColorIndex ? ACCENT_COLORS[appTheme][accentColorIndex] : undefined;
  const onRampChain = accountByChain && CHAIN_ORDER.find((chain) => accountByChain[chain]);

  const containerRef = useRef<HTMLDivElement>();
  useHorizontalScroll({ containerRef, shouldPreventDefault: true });

  const handleBuyClick = useLastCallback(() => {
    void vibrate();
    openOnRampWidgetModal({ chain: onRampChain! });
  });

  const handleDepositClick = useLastCallback(() => {
    void vibrate();
    openReceiveModal();
  });

  const handleTradeClick = useLastCallback(() => {
    void vibrate();
    startSwap();
  });

  const handleEarnClick = useLastCallback(() => {
    void vibrate();
    openStakingInfoOrStart();
  });

  const handleSellClick = useLastCallback(() => {
    void vibrate();
    openOffRampWidgetModal();
  });

  const handleSendClick = useLastCallback(() => {
    void vibrate();
    startTransfer();
  });

  const depositButton = (
    <ActionButton
      label={lang('Deposit')}
      tgsUrl={stickerPaths.iconAdd}
      previewUrl={stickerPaths.preview.iconAdd}
      accentColor={accentColor}
      onClick={handleDepositClick}
    />
  );

  if (isViewMode) {
    return <div className={styles.root}>{depositButton}</div>;
  }

  return (
    <div ref={containerRef} className={buildClassName(styles.root, 'no-scrollbar')}>
      {!isOnRampDisabled && onRampChain && (
        <ActionButton
          label={lang('Buy')}
          tgsUrl={stickerPaths.iconBuy}
          previewUrl={stickerPaths.preview.iconBuy}
          accentColor={accentColor}
          onClick={handleBuyClick}
        />
      )}
      {depositButton}
      {!isSwapDisabled && (
        <ActionButton
          label={lang('Trade')}
          tgsUrl={stickerPaths.iconSwap}
          previewUrl={stickerPaths.preview.iconSwap}
          accentColor={accentColor}
          onClick={handleTradeClick}
        />
      )}
      {!isStakingDisabled && (
        <ActionButton
          label={lang(STAKING_TAB_TEXT_VARIANTS[stakingStatus])}
          className={stakingStatus !== 'inactive' ? styles.button_purple : undefined}
          tgsUrl={stickerPaths[stakingStatus !== 'inactive' ? 'iconEarnPurple' : 'iconEarn']}
          previewUrl={stickerPaths.preview[stakingStatus !== 'inactive' ? 'iconEarnPurple' : 'iconEarn']}
          accentColor={accentColor}
          onClick={handleEarnClick}
        />
      )}
      {!isOffRampDisabled && (
        <ActionButton
          label={lang('Sell')}
          tgsUrl={stickerPaths.iconSell}
          previewUrl={stickerPaths.preview.iconSell}
          accentColor={accentColor}
          onClick={handleSellClick}
        />
      )}
      <ActionButton
        label={lang('Send')}
        tgsUrl={stickerPaths.iconSend}
        previewUrl={stickerPaths.preview.iconSend}
        accentColor={accentColor}
        onClick={handleSendClick}
      />
    </div>
  );
}

export default memo(
  withGlobal(
    (global): StateProps => {
      const accountId = selectCurrentAccountId(global);
      const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;

      return {
        isViewMode: selectIsCurrentAccountViewMode(global),
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
        isOnRampDisabled: global.restrictions.isOnRampDisabled,
        isOffRampDisabled: !selectIsOffRampAllowed(global),
        accountByChain: selectCurrentAccount(global)?.byChain,
        stakingStatus: stakingState ? getStakingStateStatus(stakingState) : 'inactive',
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(LandscapeTopActions),
);

function ActionButtonInternal({
  label, className, tgsUrl, previewUrl, accentColor, onClick,
}: ActionButtonProps) {
  const [isAnimating, play, stop] = useFlag();

  const handleClick = useLastCallback(() => {
    if (IS_TOUCH_ENV) {
      play();
    }
    onClick();
  });

  return (
    <Button
      isSimple
      className={buildClassName(styles.button, className)}
      onClick={handleClick}
      onMouseEnter={!IS_TOUCH_ENV ? play : undefined}
    >
      <AnimatedIconWithPreview
        play={isAnimating}
        size={ANIMATED_STICKER_ICON_PX}
        speed={ANIMATED_STICKER_SPEED}
        className={styles.icon}
        color={accentColor}
        nonInteractive
        forceOnHeavyAnimation
        tgsUrl={tgsUrl}
        previewUrl={previewUrl}
        onEnded={stop}
      />
      <span className={styles.label}>{label}</span>
    </Button>
  );
}

const ActionButton = memo(ActionButtonInternal);
