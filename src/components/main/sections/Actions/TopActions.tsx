import React, { memo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain } from '../../../../api/types';
import type { Theme } from '../../../../global/types';
import type { StakingStateStatus } from '../../../../util/staking';

import { ANIMATED_STICKER_ICON_PX } from '../../../../config';
import {
  selectAccountStakingState,
  selectAccountStakingStateForToken,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountTokenBalance,
  selectDefaultOffRampChain,
  selectDefaultOnRampChain,
  selectHasAccountAddresses,
  selectIsCurrentAccountViewMode,
  selectIsOffRampAllowed,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
} from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import { getIsSupportedChain } from '../../../../util/chain';
import getTestId from '../../../../util/getTestId';
import { vibrate } from '../../../../util/haptics';
import { getIsActiveStakingState, getIsNewStakeAllowed, getStakingStateStatus } from '../../../../util/staking';
import { SWIPE_DISABLED_CLASS_NAME } from '../../../../util/swipeController';
import { getChainBySlug } from '../../../../util/tokens';
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
  testId?: string;
  onClick: NoneToVoidFunction;
}

interface OwnProps {
  /** Not taken from the global state, so a screen fading out keeps its own actions */
  tokenSlug?: string;
  isActive?: boolean;
  className?: string;
}

interface StateProps {
  isViewMode: boolean;
  hasAddresses: boolean;
  isSwapDisabled?: boolean;
  isEarnHidden: boolean;
  isOnRampDisabled?: boolean;
  isOffRampDisabled?: boolean;
  onRampChain?: ApiChain;
  receiveChain?: ApiChain;
  /** Set on a token screen whose token can be bought and sold through the swap */
  tradeTokenSlug?: string;
  hasTradeTokenBalance?: boolean;
  stakingStatus: StakingStateStatus;
  theme: Theme;
  accentColorIndex?: number;
}

function TopActions({
  tokenSlug,
  isViewMode,
  hasAddresses,
  isSwapDisabled,
  isEarnHidden,
  isOnRampDisabled,
  isOffRampDisabled,
  onRampChain,
  receiveChain,
  tradeTokenSlug,
  hasTradeTokenBalance,
  stakingStatus,
  theme,
  accentColorIndex,
  className,
  isActive,
}: OwnProps & StateProps) {
  const {
    startTransfer,
    startSwap,
    startTokenSwap,
    startTokenTrade,
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

  const isBuyShown = Boolean(tradeTokenSlug) || !isOnRampDisabled;
  const isSellShown = tradeTokenSlug ? hasTradeTokenBalance : !isOffRampDisabled;

  const handleBuyClick = useLastCallback(() => {
    if (tradeTokenSlug) {
      vibrate();
      startTokenTrade({ tokenSlug: tradeTokenSlug, direction: 'buy' });
      return;
    }

    if (!onRampChain) return;

    vibrate();
    openOnRampWidgetModal({ chain: onRampChain });
  });

  const handleDepositClick = useLastCallback(() => {
    vibrate();
    openReceiveModal(receiveChain ? { chain: receiveChain } : undefined);
  });

  const handleTradeClick = useLastCallback(() => {
    vibrate();
    if (tradeTokenSlug) {
      startTokenSwap({ tokenSlug: tradeTokenSlug });
    } else {
      startSwap();
    }
  });

  const handleEarnClick = useLastCallback(() => {
    vibrate();
    openStakingInfoOrStart();
  });

  const handleSellClick = useLastCallback(() => {
    vibrate();

    if (tradeTokenSlug) {
      startTokenTrade({ tokenSlug: tradeTokenSlug, direction: 'sell' });
    } else {
      openOffRampWidgetModal();
    }
  });

  const handleSendClick = useLastCallback(() => {
    vibrate();
    startTransfer();
  });

  // Home shares its action ids with the portrait header, a token screen has its own
  function getActionTestId(homeId?: string, tokenId?: string) {
    const id = tokenSlug ? tokenId : homeId;

    return isActive && id ? getTestId(id) : undefined;
  }

  const depositButton = (
    <ActionButton
      label={lang('Fund')}
      tgsUrl={stickerPaths.iconAdd}
      previewUrl={stickerPaths.preview.iconAdd}
      accentColor={accentColor}
      testId={getActionTestId('header_action_fund', 'token_receive')}
      onClick={handleDepositClick}
    />
  );

  if (isViewMode) {
    if (!hasAddresses) return undefined;

    return (
      <div className={buildClassName(styles.root, SWIPE_DISABLED_CLASS_NAME, className)}>{depositButton}</div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={buildClassName(styles.root, 'no-scrollbar', SWIPE_DISABLED_CLASS_NAME, className)}
    >
      {isBuyShown && (
        <ActionButton
          label={lang('Buy')}
          tgsUrl={stickerPaths.iconBuy}
          previewUrl={stickerPaths.preview.iconBuy}
          accentColor={accentColor}
          testId={getActionTestId(undefined, 'token_buy')}
          onClick={handleBuyClick}
        />
      )}
      {depositButton}
      <ActionButton
        label={lang('Send')}
        tgsUrl={stickerPaths.iconSend}
        previewUrl={stickerPaths.preview.iconSend}
        accentColor={accentColor}
        testId={getActionTestId('header_action_send')}
        onClick={handleSendClick}
      />
      {!isSwapDisabled && (
        <ActionButton
          label={lang('Trade')}
          tgsUrl={stickerPaths.iconSwap}
          previewUrl={stickerPaths.preview.iconSwap}
          accentColor={accentColor}
          testId={getActionTestId('header_action_swap')}
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
          testId={getActionTestId('header_action_earn')}
          onClick={handleEarnClick}
        />
      )}
      {isSellShown && (
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
    (global, { tokenSlug }): StateProps => {
      const accountId = selectCurrentAccountId(global);
      const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;
      const tokenChain = tokenSlug ? getChainBySlug(tokenSlug) : undefined;
      const receiveChain = getIsSupportedChain(tokenChain) ? tokenChain : undefined;
      const tokenStakingState = accountId && tokenSlug !== undefined
        ? selectAccountStakingStateForToken(global, accountId, tokenSlug)
        : undefined;
      const isEarnHidden = selectIsStakingDisabled(global)
        || (tokenSlug !== undefined && !tokenStakingState)
        || Boolean(
          tokenStakingState
          && !getIsNewStakeAllowed(tokenSlug)
          && !getIsActiveStakingState(tokenStakingState),
        );

      // Neither button carries a chain of its own, so each is answered for the very chain its click will open
      const onRampChain = selectDefaultOnRampChain(global);
      const isSwapDisabled = selectIsSwapDisabled(global);

      // On a token screen, Buy and Sell trade that token; LP tokens and tokens the swap does not know stay with the card widgets
      const canTradeToken = tokenSlug !== undefined
        && !isSwapDisabled
        && global.tokenInfo.bySlug[tokenSlug]?.type !== 'lp_token'
        && Boolean(global.swapTokenInfo.bySlug[tokenSlug]);
      const tradeTokenSlug = canTradeToken ? tokenSlug : undefined;

      return {
        isViewMode: selectIsCurrentAccountViewMode(global),
        hasAddresses: accountId ? selectHasAccountAddresses(global, accountId) : false,
        isSwapDisabled,
        isEarnHidden,
        isOnRampDisabled: !onRampChain,
        isOffRampDisabled: !selectIsOffRampAllowed(global, selectDefaultOffRampChain(global)),
        onRampChain,
        receiveChain,
        tradeTokenSlug,
        hasTradeTokenBalance: tradeTokenSlug
          ? selectCurrentAccountTokenBalance(global, tradeTokenSlug) > 0n
          : undefined,
        stakingStatus: stakingState ? getStakingStateStatus(stakingState) : 'inactive',
        theme: global.settings.theme,
        accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(TopActions),
);

function ActionButtonInternal({
  label, className, tgsUrl, previewUrl, accentColor, testId, onClick,
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
      testId={testId}
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
