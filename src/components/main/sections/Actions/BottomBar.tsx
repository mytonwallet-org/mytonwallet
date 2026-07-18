import React, {
  memo, useState,
} from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { Theme } from '../../../../global/types';

import { IS_FEATURE_LIMITED } from '../../../../config';
import { selectCurrentAccountSettings } from '../../../../global/selectors';
import { ACCENT_COLORS } from '../../../../util/accentColor/constants';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFlag from '../../../../hooks/useFlag';
import { getIsBottomBarHidden, subscribeToBottomBarVisibility } from '../../../../hooks/useHideBottomBar';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useDraggablePill from './hooks/useDraggablePill';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';
import Pill from './Pill';

import styles from './BottomBar.module.scss';

interface StateProps {
  theme: Theme;
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  accentColorIndex?: number;
}

type IconKey = 'iconWallet' | 'iconAgent' | 'iconExplore' | 'iconSettings';

interface TabConfig {
  index: number;
  label: string;
  iconKey: IconKey;
  onClick: NoneToVoidFunction;
}

const ICON_SIZE_PX = 38;
const ANIMATED_STICKER_SPEED = 2;

const TAB_WALLET = 0;
const TAB_AGENT = 1;
const TAB_EXPLORE = 2;
const TAB_SETTINGS_FULL = 3;

const TAB_COUNT = IS_FEATURE_LIMITED ? 2 : 4;
const SETTINGS_INDEX = IS_FEATURE_LIMITED ? 1 : TAB_SETTINGS_FULL;

function BottomBar({
  theme, areSettingsOpen, isAgentOpen, isExploreOpen, accentColorIndex,
}: StateProps) {
  const { switchToWallet, switchToAgent, switchToExplore, switchToSettings } = getActions();

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

  const activeIndex = getActiveIndex({ isAgentOpen, isExploreOpen, areSettingsOpen });

  const tabs: TabConfig[] = IS_FEATURE_LIMITED
    ? [
      { index: TAB_WALLET, label: 'Wallet', iconKey: 'iconWallet', onClick: switchToWallet },
      { index: SETTINGS_INDEX, label: 'Settings', iconKey: 'iconSettings', onClick: switchToSettings },
    ]
    : [
      { index: TAB_WALLET, label: 'Wallet', iconKey: 'iconWallet', onClick: switchToWallet },
      { index: TAB_AGENT, label: 'Agent', iconKey: 'iconAgent', onClick: switchToAgent },
      { index: TAB_EXPLORE, label: 'Explore', iconKey: 'iconExplore', onClick: switchToExplore },
      { index: SETTINGS_INDEX, label: 'Settings', iconKey: 'iconSettings', onClick: switchToSettings },
    ];

  const switchToTabByIndex = useLastCallback((index: number) => {
    tabs.find((tab) => tab.index === index)?.onClick();
  });

  const {
    capsuleRef,
    isDragging,
    squeeze,
    renderedActiveIndex,
    pointerHandlers,
  } = useDraggablePill({
    tabCount: TAB_COUNT,
    activeIndex,
    onCommit: switchToTabByIndex,
  });

  const rootStyle = buildStyle(
    `--tab-count: ${TAB_COUNT}`,
    `--active-index: ${activeIndex}`,
  );

  return (
    <div
      className={buildClassName(styles.root, isHidden && styles.hidden)}
      style={rootStyle}
    >
      <div
        ref={capsuleRef}
        className={buildClassName(styles.capsule, isDragging && styles.dragging)}
        {...pointerHandlers}
      >
        <Pill isDragging={isDragging} squeeze={squeeze} />
        {tabs.map(({ index, label, iconKey, onClick }) => {
          const isActive = renderedActiveIndex === index;
          const variant = isActive ? `${iconKey}Solid` as const : iconKey;

          return (
            <TabButton
              key={index}
              isActive={isActive}
              label={lang(label)}
              tgsUrl={stickerPaths[variant]}
              previewUrl={stickerPaths.preview[variant]}
              accentColor={accentColor}
              onClick={onClick}
            />
          );
        })}
      </div>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { areSettingsOpen, isAgentOpen, isExploreOpen } = global;

  return {
    theme: global.settings.theme,
    areSettingsOpen,
    isAgentOpen,
    isExploreOpen,
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
  };
})(BottomBar));

const TabButton = memo(({
  isActive, label, tgsUrl, previewUrl, accentColor, onClick,
}: {
  isActive?: boolean;
  label: string;
  tgsUrl: string;
  previewUrl: string;
  accentColor?: string;
  onClick: NoneToVoidFunction;
}) => {
  const [isAnimating, startAnimation, stopAnimation] = useFlag();

  const handleClick = useLastCallback(() => {
    startAnimation();
    onClick();
  });

  return (
    <Button
      isSimple
      className={buildClassName(styles.button, isActive && styles.active)}
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

function getActiveIndex({
  isAgentOpen, isExploreOpen, areSettingsOpen,
}: Pick<StateProps, 'isAgentOpen' | 'isExploreOpen' | 'areSettingsOpen'>) {
  if (IS_FEATURE_LIMITED) {
    return areSettingsOpen ? SETTINGS_INDEX : TAB_WALLET;
  }

  if (isAgentOpen) return TAB_AGENT;
  if (isExploreOpen) return TAB_EXPLORE;
  if (areSettingsOpen) return TAB_SETTINGS_FULL;

  return TAB_WALLET;
}
