import React, { memo, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { Theme } from '../../../../global/types';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFlag from '../../../../hooks/useFlag';
import { getIsBottomBarHidden, subscribeToBottomBarVisibility } from '../../../../hooks/useHideBottomBar';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './BottomBar.module.scss';

interface StateProps {
  theme: Theme;
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
}

const ICON_SIZE_PX = 38;
const ANIMATED_STICKER_SPEED = 2;

function BottomBar({
  theme, areSettingsOpen, isAgentOpen, isExploreOpen,
}: StateProps) {
  const { switchToWallet, switchToAgent, switchToExplore, switchToSettings } = getActions();

  const lang = useLang();
  const [isHidden, setIsHidden] = useState(getIsBottomBarHidden());
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];

  useEffectOnce(() => {
    return subscribeToBottomBarVisibility(() => {
      setIsHidden(getIsBottomBarHidden());
    });
  });

  const isWalletTabActive = !isAgentOpen && !isExploreOpen && !areSettingsOpen;
  const tabCount = IS_CORE_WALLET ? 2 : 4;
  const activeIndex = getActiveIndex({ isAgentOpen, isExploreOpen, areSettingsOpen });
  const rootStyle = buildStyle(
    `--tab-count: ${tabCount}`,
    `--active-index: ${activeIndex}`,
  );

  return (
    <div
      className={buildClassName(styles.root, isHidden && styles.hidden)}
      style={rootStyle}
    >
      <div className={styles.capsule}>
        <div className={styles.pill} />
        <TabButton
          isActive={isWalletTabActive}
          label={lang('Wallet')}
          tgsUrl={isWalletTabActive ? stickerPaths.iconWalletSolid : stickerPaths.iconWallet}
          previewUrl={isWalletTabActive ? stickerPaths.preview.iconWalletSolid : stickerPaths.preview.iconWallet}
          onClick={switchToWallet}
        />
        {!IS_CORE_WALLET && (
          <>
            <TabButton
              isActive={isAgentOpen}
              label={lang('Agent')}
              tgsUrl={isAgentOpen ? stickerPaths.iconAgentSolid : stickerPaths.iconAgent}
              previewUrl={isAgentOpen ? stickerPaths.preview.iconAgentSolid : stickerPaths.preview.iconAgent}
              onClick={switchToAgent}
            />
            <TabButton
              isActive={isExploreOpen}
              label={lang('Explore')}
              tgsUrl={isExploreOpen ? stickerPaths.iconExploreSolid : stickerPaths.iconExplore}
              previewUrl={isExploreOpen ? stickerPaths.preview.iconExploreSolid : stickerPaths.preview.iconExplore}
              onClick={switchToExplore}
            />
          </>
        )}
        <TabButton
          isActive={areSettingsOpen}
          label={lang('Settings')}
          tgsUrl={areSettingsOpen ? stickerPaths.iconSettingsSolid : stickerPaths.iconSettings}
          previewUrl={areSettingsOpen ? stickerPaths.preview.iconSettingsSolid : stickerPaths.preview.iconSettings}
          onClick={switchToSettings}
        />
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
  };
})(BottomBar));

function TabButton({
  label, tgsUrl, previewUrl, isActive, onClick,
}: {
  isActive?: boolean;
  label: string;
  tgsUrl: string;
  previewUrl: string;
  onClick: NoneToVoidFunction;
}) {
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
        tgsUrl={tgsUrl}
        previewUrl={previewUrl}
        onEnded={stopAnimation}
      />
      <span className={styles.label}>{label}</span>
    </Button>
  );
}

function getActiveIndex({
  isAgentOpen, isExploreOpen, areSettingsOpen,
}: Pick<StateProps, 'isAgentOpen' | 'isExploreOpen' | 'areSettingsOpen'>) {
  if (IS_CORE_WALLET) {
    return areSettingsOpen ? 1 : 0;
  }

  if (isAgentOpen) return 1;
  if (isExploreOpen) return 2;
  if (areSettingsOpen) return 3;

  return 0;
}
