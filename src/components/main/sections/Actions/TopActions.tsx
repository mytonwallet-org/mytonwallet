import React, { memo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Theme } from '../../../../global/types';
import type { StakingStateStatus } from '../../../../util/staking';

import { ANIMATED_STICKER_ICON_PX } from '../../../../config';
import {
  selectAccountStakingState,
  selectAccountStakingStatesBySlug,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectDefaultOffRampChain,
  selectDefaultOnRampChain,
  selectIsCurrentAccountViewMode,
  selectIsOffRampAllowed,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
} from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import { vibrate } from '../../../../util/haptics';
import { getIsActiveStakingState, getIsNewStakeAllowed, getStakingStateStatus } from '../../../../util/staking';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../../util/swipeController';
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

import styles from './TopActions.module.scss';

const ANIMATED_STICKER_SPEED = 2;

interface ActionButtonProps {
  label: string;
  className?: string;
  tgsUrl: string;
  previewUrl: string;
  accentColor?: string;
  onClick: NoneToVoidFunction;
}

interface OwnProps {
  className?: string;
}

interface StateProps {
  isViewMode: boolean;
  isSwapDisabled?: boolean;
  isEarnHidden: boolean;
  isOnRampDisabled?: boolean;
  isOffRampDisabled?: boolean;
  onRampChain?: ApiChain;
  stakingStatus: StakingStateStatus;
  theme: Theme;
  accentColorIndex?: number;
}

function TopActions({
  isViewMode,
  isSwapDisabled,
  isEarnHidden,
  isOnRampDisabled,
  isOffRampDisabled,
  onRampChain,
  stakingStatus,
  theme,
  accentColorIndex,
  className,
}: OwnProps & StateProps) {
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

  const containerRef = useRef<HTMLDivElement>();
  useHorizontalScroll({ containerRef, shouldPreventDefault: true });

  const handleBuyClick = useLastCallback(() => {
    if (!onRampChain) return;

    vibrate();
    openOnRampWidgetModal({ chain: onRampChain });
  });

  const handleDepositClick = useLastCallback(() => {
    vibrate();
    openReceiveModal();
  });

  const handleTradeClick = useLastCallback(() => {
    vibrate();
    startSwap();
  });

  const handleEarnClick = useLastCallback(() => {
    vibrate();
    openStakingInfoOrStart();
  });

  const handleSellClick = useLastCallback(() => {
    vibrate();
    openOffRampWidgetModal();
  });

  const handleSendClick = useLastCallback(() => {
    vibrate();
    startTransfer();
  });

  const depositButton = (
    <ActionButton
      label={lang('Fund')}
      tgsUrl={stickerPaths.iconAdd}
      previewUrl={stickerPaths.preview.iconAdd}
      accentColor={accentColor}
      onClick={handleDepositClick}
    />
  );

  if (isViewMode) {
    return (
      <div className={buildClassName(styles.root, SWIPE_DISABLED_CLASS_NAME, className)}>{depositButton}</div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={buildClassName(styles.root, 'no-scrollbar', SWIPE_DISABLED_CLASS_NAME, className)}
    >
      {!isOnRampDisabled && (
        <ActionButton
          label={lang('Buy')}
          tgsUrl={stickerPaths.iconBuy}
          previewUrl={stickerPaths.preview.iconBuy}
          accentColor={accentColor}
          onClick={handleBuyClick}
        />
      )}
      {depositButton}
      <ActionButton
        label={lang('Send')}
        tgsUrl={stickerPaths.iconSend}
        previewUrl={stickerPaths.preview.iconSend}
        accentColor={accentColor}
        onClick={handleSendClick}
      />
      {!isSwapDisabled && (
        <ActionButton
          label={lang('Trade')}
          tgsUrl={stickerPaths.iconSwap}
          previewUrl={stickerPaths.preview.iconSwap}
          accentColor={accentColor}
          onClick={handleTradeClick}
        />
      )}
      {!isEarnHidden && (
        <ActionButton
          label={lang(STAKING_TAB_TEXT_VARIANTS[stakingStatus])}
          className={stakingStatus !== 'inactive' ? styles.button_purple : undefined}
          tgsUrl={stickerPaths[stakingStatus !== 'inactive' ? 'iconEarnPurple' : 'iconEarn']}
          previewUrl={stickerPaths.preview[stakingStatus !== 'inactive' ? 'iconEarnPurple' : 'iconEarn']}
          accentColor={stakingStatus === 'inactive' ? accentColor : undefined}
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
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountId = selectCurrentAccountId(global);
      const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;
      const currentTokenSlug = selectCurrentAccountState(global)?.currentTokenSlug;
      const stakingStatesBySlug = accountId ? selectAccountStakingStatesBySlug(global, accountId) : undefined;
      const currentStakingState = currentTokenSlug !== undefined ? stakingStatesBySlug?.[currentTokenSlug] : undefined;
      const isEarnHidden = selectIsStakingDisabled(global)
        || (currentTokenSlug !== undefined && !currentStakingState)
        || Boolean(
          currentStakingState
          && !getIsNewStakeAllowed(currentTokenSlug)
          && !getIsActiveStakingState(currentStakingState),
        );

      // Neither button carries a chain of its own, so each is answered for the very chain its click will open
      const onRampChain = selectDefaultOnRampChain(global);

      return {
        isViewMode: selectIsCurrentAccountViewMode(global),
        isSwapDisabled: selectIsSwapDisabled(global),
        isEarnHidden,
        isOnRampDisabled: !onRampChain,
        isOffRampDisabled: !selectIsOffRampAllowed(global, selectDefaultOffRampChain(global)),
        onRampChain,
        stakingStatus: stakingState ? getStakingStateStatus(stakingState) : 'inactive',
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(TopActions),
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
