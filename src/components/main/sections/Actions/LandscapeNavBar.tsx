import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { NavigationTab, Theme } from '../../../../global/types';
import { ContentTab } from '../../../../global/types';

import { selectCurrentAccountSettings } from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import getTestId from '../../../../util/getTestId';
import { getNavigationTabShift, resolveNavigationTabOrder } from '../../../../util/navigationTabOrder';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useNavigationTabDrag from '../../../../hooks/useNavigationTabDrag';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './LandscapeNavBar.module.scss';

const ANIMATED_ICON_SIZE_PX = 34;
const ANIMATED_STICKER_SPEED = 2;

type IconKey = 'iconWallet' | 'iconMarket' | 'iconAgent' | 'iconExplore' | 'iconSettings';

interface StateProps {
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isMarketOpen?: boolean;
  theme: Theme;
  accentColorIndex?: number;
  navigationTabOrder?: NavigationTab[];
}

const TAB_LABELS: Record<NavigationTab, string> = {
  wallet: 'Wallet',
  market: 'Market',
  agent: 'Agent',
  explore: 'Explore',
  settings: 'Settings',
};

const TAB_ICON_KEYS: Record<NavigationTab, IconKey> = {
  wallet: 'iconWallet',
  market: 'iconMarket',
  agent: 'iconAgent',
  explore: 'iconExplore',
  settings: 'iconSettings',
};

function LandscapeNavBar({
  areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen, theme, accentColorIndex, navigationTabOrder,
}: StateProps) {
  const {
    switchToWallet, switchToAgent, switchToExplore, switchToMarket, switchToSettings,
    closeNftCollection, selectToken, setActiveContentTab, setNavigationTabOrder,
  } = getActions();

  const rootRef = useRef<HTMLDivElement>();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];
  const accentColor = accentColorIndex !== undefined ? ACCENT_COLORS[appTheme][accentColorIndex] : undefined;
  const order = useMemo(() => resolveNavigationTabOrder(navigationTabOrder), [navigationTabOrder]);
  const {
    drag, isSettling, consumeDragEndClick, pointerHandlers,
  } = useNavigationTabDrag({
    rootRef,
    tabClassName: styles.button,
    axis: 'y',
    order,
    onReorder: (newOrder) => setNavigationTabOrder({ order: newOrder }),
  });

  const isWalletActive = !areSettingsOpen && !isAgentOpen && !isExploreOpen && !isMarketOpen;
  const activeTabs: Record<NavigationTab, boolean | undefined> = {
    wallet: isWalletActive,
    market: isMarketOpen,
    agent: isAgentOpen,
    explore: isExploreOpen,
    settings: areSettingsOpen,
  };

  const handleWalletClick = useLastCallback(() => {
    switchToWallet();
    closeNftCollection();
    selectToken({ slug: undefined });
    setActiveContentTab({ tab: ContentTab.Overview });
  });

  const handleTabClick = useLastCallback((tab: NavigationTab) => {
    if (consumeDragEndClick()) return;

    const openTab: Record<NavigationTab, NoneToVoidFunction> = {
      wallet: handleWalletClick,
      market: switchToMarket,
      agent: switchToAgent,
      explore: switchToExplore,
      settings: switchToSettings,
    };
    openTab[tab]();
  });

  return (
    <div
      ref={rootRef}
      className={styles.root}
      {...pointerHandlers}
    >
      {order.map((tab, index) => {
        const isActive = activeTabs[tab];
        const iconKey = TAB_ICON_KEYS[tab];
        const variant = isActive ? `${iconKey}Solid` as const : iconKey;

        return (
          <NavButton
            key={tab}
            tab={tab}
            isActive={isActive}
            isDragged={drag?.fromIndex === index}
            shouldAnimateShift={!isSettling}
            shift={getNavigationTabShift(index, drag)}
            label={lang(TAB_LABELS[tab])}
            tgsUrl={stickerPaths[variant]}
            previewUrl={stickerPaths.preview[variant]}
            accentColor={accentColor}
            onClick={handleTabClick}
          />
        );
      })}
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen } = global;

  return {
    areSettingsOpen,
    isAgentOpen,
    isExploreOpen,
    isMarketOpen,
    theme: global.settings.theme,
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
    navigationTabOrder: global.settings.navigationTabOrder,
  };
})(LandscapeNavBar));

function NavButtonInternal({
  tab, label, tgsUrl, previewUrl, isActive, isDragged, shouldAnimateShift, shift, accentColor, onClick,
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
}) {
  const [isAnimating, startAnimation, stopAnimation] = useFlag();

  const handleClick = useLastCallback(() => {
    if (IS_TOUCH_ENV) startAnimation();
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
      style={shift ? `transform: translateY(${shift}px)` : undefined}
      testId={getTestId(tab === 'settings' ? 'tab_settings_button' : `tab_${tab}`)}
      onClick={handleClick}
      onMouseEnter={!IS_TOUCH_ENV ? startAnimation : undefined}
    >
      <AnimatedIconWithPreview
        play={isAnimating}
        size={ANIMATED_ICON_SIZE_PX}
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
}

const NavButton = memo(NavButtonInternal);
