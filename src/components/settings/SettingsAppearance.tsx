import React, {
  memo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { AnimationLevel, Theme } from '../../global/types';

import {
  ANIMATION_LEVEL_MAX,
  ANIMATION_LEVEL_MIN,
  IS_CAPACITOR,
  IS_CORE_WALLET,
} from '../../config';
import { selectCurrentAccountSettings } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { switchToAir } from '../../util/capacitor';
import { pause } from '../../util/schedulers';
import switchAnimationLevel from '../../util/switchAnimationLevel';
import switchTheme from '../../util/switchTheme';
import { IS_ELECTRON, IS_WINDOWS } from '../../util/windowEnvironment';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import CustomCardPreview from '../main/modals/accountSelector/CustomCardPreview';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

import airImg from '../../assets/settings/settings_air.svg';
import darkThemeImg from '../../assets/theme/theme_dark.png';
import lightThemeImg from '../../assets/theme/theme_light.png';
import systemThemeImg from '../../assets/theme/theme_system.png';

interface OwnProps {
  isActive?: boolean;
  theme: Theme;
  handleBackClick: () => void;
  animationLevel: AnimationLevel;
  isInsideModal?: boolean;
  isTrayIconEnabled: boolean;
  onTrayIconEnabledToggle: VoidFunction;
}

interface StateProps {
  cardBackgroundNft?: ApiNft;
  isNftBuyingDisabled: boolean;
  isSeasonalThemingDisabled?: boolean;
}

const SWITCH_THEME_DURATION_MS = 300;
const SWITCH_APPLICATION_DURATION_MS = 300;
const THEME_OPTIONS = [{
  value: 'light',
  name: 'Light',
  icon: lightThemeImg,
}, {
  value: 'system',
  name: 'System',
  icon: systemThemeImg,
}, {
  value: 'dark',
  name: 'Dark',
  icon: darkThemeImg,
}];

function SettingsAppearance({
  isActive,
  theme,
  animationLevel,
  cardBackgroundNft,
  isInsideModal,
  isTrayIconEnabled,
  isNftBuyingDisabled,
  isSeasonalThemingDisabled,
  onTrayIconEnabledToggle,
  handleBackClick,
}: OwnProps & StateProps) {
  const {
    setTheme,
    setAnimationLevel,
    openCustomizeWalletModal,
    toggleSeasonalTheming,
  } = getActions();

  const lang = useLang();
  const [isAirVersionEnabled, setIsAirVersionEnabled] = useState(false);

  useHistoryBack({
    isActive,
    onBack: handleBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const handleAirVersionSwitch = useLastCallback(async () => {
    setIsAirVersionEnabled(true);

    await pause(SWITCH_APPLICATION_DURATION_MS);

    switchToAir();
  });

  const handleThemeChange = useLastCallback((newTheme: string) => {
    document.documentElement.classList.add('no-transitions');
    setTheme({ theme: newTheme as Theme });
    switchTheme(newTheme as Theme, isInsideModal);
    setTimeout(() => {
      document.documentElement.classList.remove('no-transitions');
    }, SWITCH_THEME_DURATION_MS);
  });

  const handleAnimationLevelToggle = useLastCallback(() => {
    const level = animationLevel === ANIMATION_LEVEL_MIN ? ANIMATION_LEVEL_MAX : ANIMATION_LEVEL_MIN;
    setAnimationLevel({ level });
    switchAnimationLevel(level);
  });

  const handleSeasonalThemingToggle = useLastCallback(() => {
    toggleSeasonalTheming({ isEnabled: isSeasonalThemingDisabled });
  });

  const handleCustomizeWalletClick = useLastCallback(() => {
    openCustomizeWalletModal({ returnTo: 'settings' });
    return false;
  });

  function renderAirSwitcher() {
    return (
      <>
        <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
          <div className={styles.item} onClick={handleAirVersionSwitch}>
            <img className={styles.menuIcon} src={airImg} alt="" aria-hidden />
            MyTonWallet Air

            <Switcher
              className={styles.menuSwitcher}
              label="MyTonWallet Air"
              checked={isAirVersionEnabled}
            />
          </div>
        </div>
        <p className={styles.blockDescription}>
          {lang('$try_new_air_version')}
        </p>
      </>
    );
  }

  function renderThemes() {
    return THEME_OPTIONS.map(({ name, value, icon }) => {
      return (
        <div
          key={value}
          className={buildClassName(styles.theme, value === theme && styles.theme_active)}
          onClick={() => handleThemeChange(value)}
        >
          <div className={buildClassName(styles.themeIcon, value === theme && styles.themeIcon_active)}>
            <img src={icon} alt="" className={styles.themeImg} aria-hidden />
          </div>
          <span>{lang(name)}</span>
        </div>
      );
    });
  }

  function renderPalleteIcon() {
    return (
      <div className={styles.palleteIcon}>
        <div className={styles.miniCard}>
          <CustomCardPreview nft={cardBackgroundNft} className={styles.miniCardPreview} />
        </div>
      </div>
    );
  }

  return (
    <div className={styles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('Appearance')}
          withNotch={isScrolled}
          onBackButtonClick={handleBackClick}
          className={styles.modalHeader}
        />
      ) : (
        <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={handleBackClick} className={styles.headerBack}>
            <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={styles.headerTitle}>{lang('Appearance')}</span>
        </div>
      )}

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {IS_CAPACITOR && renderAirSwitcher()}

        <p className={styles.blockTitle}>{lang('Theme')}</p>
        <div className={styles.settingsBlock}>
          <div className={styles.themeWrapper}>
            {renderThemes()}
          </div>
        </div>

        {!IS_CORE_WALLET && !isNftBuyingDisabled && (
          <>
            <p className={styles.blockTitle}>{lang('Palette and Card')}</p>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <a
                role="button"
                tabIndex={0}
                className={buildClassName(styles.item, styles.itemWithFixedHeight)}
                onClick={handleCustomizeWalletClick}
              >
                {renderPalleteIcon()}
                {lang('Customize Wallet')}

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </a>
            </div>
            <p className={styles.blockDescription}>
              {lang('Customize the wallet\'s home screen and color accents the way you like.')}
            </p>
          </>
        )}

        <p className={styles.blockTitle}>{lang('Other')}</p>
        <div className={styles.settingsBlock}>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleAnimationLevelToggle}>
            {lang('Enable Animations')}

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Enable Animations')}
              checked={animationLevel !== ANIMATION_LEVEL_MIN}
            />
          </div>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleSeasonalThemingToggle}>
            {lang('Enable Seasonal Theming')}

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Enable Seasonal Theming')}
              checked={!isSeasonalThemingDisabled}
            />
          </div>
          {IS_ELECTRON && IS_WINDOWS && (
            <div className={buildClassName(styles.item, styles.item_small)} onClick={onTrayIconEnabledToggle}>
              {lang('Display Tray Icon')}

              <Switcher
                className={styles.menuSwitcher}
                label={lang('Display Tray Icon')}
                checked={isTrayIconEnabled}
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountSettings = selectCurrentAccountSettings(global);

  return {
    cardBackgroundNft: accountSettings?.cardBackgroundNft,
    isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
    isSeasonalThemingDisabled: global.settings.isSeasonalThemingDisabled,
  };
})(SettingsAppearance));
