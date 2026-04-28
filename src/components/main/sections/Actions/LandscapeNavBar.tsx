import React, { memo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { Theme } from '../../../../global/types';
import { ContentTab } from '../../../../global/types';

import { IS_CORE_WALLET } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { IS_TOUCH_ENV } from '../../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';

import styles from './LandscapeNavBar.module.scss';

const ANIMATED_ICON_SIZE_PX = 34;
const ANIMATED_STICKER_SPEED = 2;

interface StateProps {
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  theme: Theme;
}

function LandscapeNavBar({
  areSettingsOpen, isAgentOpen, isExploreOpen, theme,
}: StateProps) {
  const {
    switchToWallet, switchToAgent, switchToExplore, switchToSettings,
    closeNftCollection, selectToken, setActiveContentTab,
  } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const stickerPaths = ANIMATED_STICKERS_PATHS[appTheme];

  const isWalletActive = !areSettingsOpen && !isAgentOpen && !isExploreOpen;

  const handleWalletClick = useLastCallback(() => {
    switchToWallet();
    closeNftCollection();
    selectToken({ slug: undefined });
    setActiveContentTab({ tab: ContentTab.Overview });
  });

  return (
    <div className={styles.root}>
      <NavButton
        isActive={isWalletActive}
        label={lang('Wallet')}
        tgsUrl={isWalletActive ? stickerPaths.iconWalletSolid : stickerPaths.iconWallet}
        previewUrl={isWalletActive ? stickerPaths.preview.iconWalletSolid : stickerPaths.preview.iconWallet}
        onClick={handleWalletClick}
      />
      {!IS_CORE_WALLET && (
        <>
          <NavButton
            isActive={isAgentOpen}
            label={lang('Agent')}
            tgsUrl={isAgentOpen ? stickerPaths.iconAgentSolid : stickerPaths.iconAgent}
            previewUrl={isAgentOpen ? stickerPaths.preview.iconAgentSolid : stickerPaths.preview.iconAgent}
            onClick={switchToAgent}
          />
          <NavButton
            isActive={isExploreOpen}
            label={lang('Explore')}
            tgsUrl={isExploreOpen ? stickerPaths.iconExploreSolid : stickerPaths.iconExplore}
            previewUrl={isExploreOpen ? stickerPaths.preview.iconExploreSolid : stickerPaths.preview.iconExplore}
            onClick={switchToExplore}
          />
        </>
      )}
      <NavButton
        isActive={areSettingsOpen}
        label={lang('Settings')}
        tgsUrl={areSettingsOpen ? stickerPaths.iconSettingsSolid : stickerPaths.iconSettings}
        previewUrl={areSettingsOpen ? stickerPaths.preview.iconSettingsSolid : stickerPaths.preview.iconSettings}
        onClick={switchToSettings}
      />
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { areSettingsOpen, isAgentOpen, isExploreOpen } = global;

  return {
    areSettingsOpen,
    isAgentOpen,
    isExploreOpen,
    theme: global.settings.theme,
  };
})(LandscapeNavBar));

function NavButtonInternal({
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
    if (IS_TOUCH_ENV) startAnimation();
    onClick();
  });

  return (
    <Button
      isSimple
      className={buildClassName(styles.button, isActive && styles.active)}
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
        tgsUrl={tgsUrl}
        previewUrl={previewUrl}
        onEnded={stopAnimation}
      />
      <span className={styles.label}>{label}</span>
    </Button>
  );
}

const NavButton = memo(NavButtonInternal);
