import React, {
  memo, useMemo, useState,
} from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { NavigationTab, Theme } from '../../../../global/types';

import { selectCurrentAccountSettings } from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import getTestId from '../../../../util/getTestId';
import { getNavigationTabShift, resolveNavigationTabOrder } from '../../../../util/navigationTabOrder';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import useDraggablePill from '../../../../hooks/useDraggablePill';
import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFlag from '../../../../hooks/useFlag';
import { getIsBottomBarHidden, subscribeToBottomBarVisibility } from '../../../../hooks/useHideBottomBar';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useNavigationTabDrag from '../../../../hooks/useNavigationTabDrag';

import Pill from '../../../common/Pill';
import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './BottomBar.module.scss';

interface StateProps {
  theme: Theme;
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isMarketOpen?: boolean;
  accentColorIndex?: number;
  navigationTabOrder?: NavigationTab[];
}

type IconKey = 'iconWallet' | 'iconMarket' | 'iconAgent' | 'iconExplore' | 'iconSettings';

interface TabConfig {
  tab: NavigationTab;
  label: string;
  iconKey: IconKey;
  onClick: NoneToVoidFunction;
}

const ICON_SIZE_PX = 38;
const ANIMATED_STICKER_SPEED = 2;

function BottomBar({
  theme, areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen, accentColorIndex, navigationTabOrder,
}: StateProps) {
  const {
    switchToWallet, switchToAgent, switchToExplore, switchToMarket, switchToSettings, setNavigationTabOrder,
  } = getActions();

  const lang = useLang();
  const [isHidden, setIsHidden] = useState(getIsBottomBarHidden());
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];
  const accentColor = accentColorIndex !== undefined ? ACCENT_COLORS[appTheme][accentColorIndex] : undefined;

  useEffectOnce(() => {
    return subscribeToBottomBarVisibility(() => {
      setIsHidden(getIsBottomBarHidden());
    });
  });

  const order = useMemo(() => resolveNavigationTabOrder(navigationTabOrder), [navigationTabOrder]);
  const activeIndex = order.indexOf(getActiveTab({ isAgentOpen, isExploreOpen, isMarketOpen, areSettingsOpen }));

  const tabConfigs: Record<NavigationTab, TabConfig> = {
    wallet: { tab: 'wallet', label: 'Wallet', iconKey: 'iconWallet', onClick: switchToWallet },
    market: { tab: 'market', label: 'Market', iconKey: 'iconMarket', onClick: switchToMarket },
    agent: { tab: 'agent', label: 'Agent', iconKey: 'iconAgent', onClick: switchToAgent },
    explore: { tab: 'explore', label: 'Explore', iconKey: 'iconExplore', onClick: switchToExplore },
    settings: { tab: 'settings', label: 'Settings', iconKey: 'iconSettings', onClick: switchToSettings },
  };
  const tabs = order.map((tab) => tabConfigs[tab]);

  const switchToTabByIndex = useLastCallback((index: number) => {
    tabs[index]?.onClick();
  });

  const {
    capsuleRef,
    isDragging,
    squeeze,
    renderedActiveIndex,
    cancelDrag,
    pointerHandlers,
  } = useDraggablePill({
    tabCount: tabs.length,
    activeIndex,
    onCommit: switchToTabByIndex,
  });

  // A tab held still lifts for reordering; a finger that slides the pill first only switches tabs
  const {
    drag, isSettling, consumeDragEndClick, pointerHandlers: reorderPointerHandlers,
  } = useNavigationTabDrag({
    rootRef: capsuleRef,
    tabClassName: styles.button,
    axis: 'x',
    order,
    isLiftBlocked: isDragging,
    onLift: cancelDrag,
    onReorder: (newOrder) => setNavigationTabOrder({ order: newOrder }),
  });

  const handlePointerDown = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    reorderPointerHandlers.onPointerDown(e);
    pointerHandlers.onPointerDown(e);
  });

  const handlePointerMove = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    reorderPointerHandlers.onPointerMove(e);
    pointerHandlers.onPointerMove(e);
  });

  const handlePointerUp = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    reorderPointerHandlers.onPointerUp(e);
    pointerHandlers.onPointerUp(e);
  });

  const handlePointerCancel = useLastCallback((e: React.PointerEvent<HTMLDivElement>) => {
    reorderPointerHandlers.onPointerCancel(e);
    pointerHandlers.onPointerCancel(e);
  });

  const handleTabClick = useLastCallback((tab: NavigationTab) => {
    if (consumeDragEndClick()) return;

    tabConfigs[tab].onClick();
  });

  // The pill stays with the active tab while tabs move: under the pointer when it is the dragged one
  const isActiveTabDragged = drag?.fromIndex === activeIndex;
  const pillShift = drag ? getNavigationTabShift(activeIndex, drag) * Math.sign(drag.step) : 0;

  const rootStyle = buildStyle(
    `--tab-count: ${tabs.length}`,
    `--active-index: ${activeIndex}`,
    Boolean(pillShift) && `--drag-offset-px: ${pillShift}px`,
  );

  return (
    <div
      className={buildClassName(styles.root, isHidden && styles.hidden)}
      style={rootStyle}
    >
      <div
        ref={capsuleRef}
        className={buildClassName(styles.capsule, isDragging && styles.dragging)}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerCancel}
        onContextMenu={reorderPointerHandlers.onContextMenu}
      >
        <Pill isDragging={isDragging || isActiveTabDragged} squeeze={squeeze} />
        {tabs.map(({ tab, label, iconKey }, index) => {
          const isActive = renderedActiveIndex === index;
          const variant = isActive ? `${iconKey}Solid` as const : iconKey;

          return (
            <TabButton
              key={tab}
              tab={tab}
              isActive={isActive}
              isDragged={drag?.fromIndex === index}
              shouldAnimateShift={!isSettling}
              shift={getNavigationTabShift(index, drag)}
              label={lang(label)}
              tgsUrl={stickerPaths[variant]}
              previewUrl={stickerPaths.preview[variant]}
              accentColor={accentColor}
              onClick={handleTabClick}
            />
          );
        })}
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen } = global;

  return {
    theme: global.settings.theme,
    areSettingsOpen,
    isAgentOpen,
    isExploreOpen,
    isMarketOpen,
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
    navigationTabOrder: global.settings.navigationTabOrder,
  };
})(BottomBar));

const TabButton = memo(({
  tab, isActive, isDragged, shouldAnimateShift, shift, label, tgsUrl, previewUrl, accentColor, onClick,
}: {
  tab: NavigationTab;
  isActive?: boolean;
  isDragged?: boolean;
  shouldAnimateShift?: boolean;
  shift: number;
  label: string;
  tgsUrl: string;
  previewUrl: string;
  accentColor?: string;
  onClick: (tab: NavigationTab) => void;
}) => {
  const [isAnimating, startAnimation, stopAnimation] = useFlag();

  const handleClick = useLastCallback(() => {
    startAnimation();
    onClick(tab);
  });

  return (
    <Button
      isSimple
      className={buildClassName(
        styles.button,
        isActive && styles.active,
        isDragged && styles.dragged,
        !isDragged && shouldAnimateShift && styles.shifting,
      )}
      style={shift ? `transform: translateX(${shift}px)` : undefined}
      testId={getTestId(tab === 'settings' ? 'tab_settings_button' : `tab_${tab}`)}
      onClick={handleClick}
    >
      <AnimatedIconWithPreview
        play={isAnimating}
        size={ICON_SIZE_PX}
        speed={ANIMATED_STICKER_SPEED}
        nonInteractive
        forceOnHeavyAnimation
        className={styles.icon}
        color={accentColor}
        tgsUrl={tgsUrl}
        previewUrl={previewUrl}
        onEnded={stopAnimation}
      />
      <span className={styles.label}>{label}</span>
    </Button>
  );
});

function getActiveTab({
  isAgentOpen, isExploreOpen, isMarketOpen, areSettingsOpen,
}: Pick<StateProps, 'isAgentOpen' | 'isExploreOpen' | 'isMarketOpen' | 'areSettingsOpen'>): NavigationTab {
  if (isAgentOpen) return 'agent';
  if (isExploreOpen) return 'explore';
  if (isMarketOpen) return 'market';
  if (areSettingsOpen) return 'settings';

  return 'wallet';
}
