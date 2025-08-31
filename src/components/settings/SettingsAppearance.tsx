import React, {
  memo, useEffect, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { AnimationLevel, Theme } from '../../global/types';

import {
  ANIMATION_LEVEL_MAX,
  ANIMATION_LEVEL_MIN,
  IS_CAPACITOR,
  IS_CORE_WALLET,
  MTW_CARDS_WEBSITE,
} from '../../config';
import {
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../global/selectors';
import { ACCENT_COLORS } from '../../util/accentColor/constants';
import buildClassName from '../../util/buildClassName';
import { switchToAir } from '../../util/capacitor';
import getAccentColorsFromNfts from '../../util/getAccentColorsFromNfts';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { openUrl } from '../../util/openUrl';
import { pause } from '../../util/schedulers';
import switchAnimationLevel from '../../util/switchAnimationLevel';
import switchTheme from '../../util/switchTheme';
import { IS_ELECTRON, IS_WINDOWS } from '../../util/windowEnvironment';

import useAppTheme from '../../hooks/useAppTheme';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import Spinner from '../ui/Spinner';
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
  isViewMode: boolean;
  accentColorIndex?: number;
  nftsByAddress?: Record<string, ApiNft>;
  nftAddresses?: string[];
  isMintingCardsAvailable?: boolean;
  isNftBuyingDisabled: boolean;
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
  accentColorIndex,
  nftAddresses,
  nftsByAddress,
  isInsideModal,
  isViewMode,
  isTrayIconEnabled,
  isMintingCardsAvailable,
  isNftBuyingDisabled,
  onTrayIconEnabledToggle,
  handleBackClick,
}: OwnProps & StateProps) {
  const {
    setTheme,
    setAnimationLevel,
    openMintCardModal,
    installAccentColorFromNft,
    clearAccentColorFromNft,
    showNotification,
  } = getActions();

  const lang = useLang();
  const [isAvailableAccentLoading, setIsAvailableAccentLoading] = useState(false);
  const [availableAccentColorIds, setAvailableAccentColorIds] = useState<number[]>(MEMO_EMPTY_ARRAY);
  const [nftByColorIndexes, setNftsByColorIndex] = useState<Record<number, ApiNft>>({});
  const [isAirVersionEnabled, setIsAirVersionEnabled] = useState(false);

  useHistoryBack({
    isActive,
    onBack: handleBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const appTheme = useAppTheme(theme);

  useEffect(() => {
    if (IS_CORE_WALLET) return;

    void (async () => {
      setIsAvailableAccentLoading(true);
      const result = await getAccentColorsFromNfts(nftAddresses, nftsByAddress);
      if (result) {
        setAvailableAccentColorIds(result.availableAccentColorIds);
        setNftsByColorIndex(result.nftsByColorIndex);
      } else {
        setAvailableAccentColorIds(MEMO_EMPTY_ARRAY);
        setNftsByColorIndex({});
      }
      setIsAvailableAccentLoading(false);
    })();
  }, [nftsByAddress, nftAddresses]);

  const sortedColors = useMemo(() => {
    return ACCENT_COLORS[appTheme]
      .map((color, index) => ({ color, index }))
      .sort((a, b) => {
        return Number(!availableAccentColorIds.includes(a.index)) - Number(!availableAccentColorIds.includes(b.index));
      });
  }, [appTheme, availableAccentColorIds]);

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

  function handleAccentColorClick(colorIndex?: number) {
    const isLocked = colorIndex !== undefined ? !availableAccentColorIds.includes(colorIndex) : false;

    if (isLocked) {
      showNotification({ message: lang('Get a unique MyTonWallet Card to unlock new palettes.') });
    } else if (colorIndex === undefined) {
      clearAccentColorFromNft();
    } else {
      installAccentColorFromNft({ nft: nftByColorIndexes[colorIndex] });
    }
  }

  const handleUnlockNewPalettesClick = useLastCallback(() => {
    if (!isViewMode && isMintingCardsAvailable) {
      openMintCardModal();
    } else {
      void openUrl(MTW_CARDS_WEBSITE);
    }
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

  function renderColorButton(color?: string, index?: number) {
    const isSelected = accentColorIndex === index;
    const isLocked = index !== undefined ? !availableAccentColorIds.includes(index) : false;

    return (
      <button
        key={color || 'default'}
        type="button"
        disabled={isSelected}
        style={color ? `--current-accent-color: ${color}` : undefined}
        className={buildClassName(styles.colorButton, isSelected && styles.colorButtonCurrent)}
        aria-label={lang('Change Palette')}
        onClick={() => handleAccentColorClick(index)}
      >
        {isAvailableAccentLoading && isLocked && <Spinner color="white" />}
        {!isAvailableAccentLoading && isLocked && (
          <i
            className={buildClassName(styles.iconLock, 'icon-lock', color === '#FFFFFF' && styles.iconLockInverted)}
            aria-hidden
          />
        )}
      </button>
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
            <p className={styles.blockTitle}>{lang('Palette')}</p>
            <div className={buildClassName(styles.block, styles.settingsBlockWithDescription)}>
              <div className={styles.colorList}>
                {renderColorButton()}
                {sortedColors.map(({ color, index }) => renderColorButton(color, index))}
              </div>
              <div
                className={styles.subBlockAsButton}
                role="button"
                tabIndex={0}
                onClick={() => handleUnlockNewPalettesClick()}
              >
                {lang('Unlock New Palettes')}
              </div>
            </div>
            <p className={styles.blockDescription}>{lang('Get a unique MyTonWallet Card to unlock new palettes.')}</p>
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
  const {
    orderedAddresses: nftAddresses,
    byAddress: nftsByAddress,
  } = selectCurrentAccountState(global)?.nfts || {};

  const { config: { cardsInfo } = {} } = selectCurrentAccountState(global) || {};

  return {
    isViewMode: selectIsCurrentAccountViewMode(global),
    accentColorIndex: selectCurrentAccountSettings(global)?.accentColorIndex,
    nftAddresses,
    nftsByAddress,
    isMintingCardsAvailable: Boolean(cardsInfo),
    isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
  };
})(SettingsAppearance));
