import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiTonWalletVersion } from '../../api/chains/ton/types';
import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type { ApiWalletWithVersionInfo } from '../../api/types';
import type { GlobalState, UserToken } from '../../global/types';
import type { Wallet } from './SettingsWalletVersion';
import { SettingsState } from '../../global/types';

import {
  APP_ENV_MARKER,
  APP_NAME,
  APP_VERSION,
  IS_CAPACITOR,
  IS_CORE_WALLET,
  IS_EXPLORER,
  IS_EXTENSION,
  LANG_LIST,
  MTW_CARDS_WEBSITE,
  PROXY_HOSTS,
  SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY,
  SUPPORT_USERNAME,
  TONCOIN,
} from '../../config';
import { getHelpCenterUrl } from '../../global/helpers/getHelpCenterUrl';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
  selectIsPasswordPresent,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { toBig, toDecimal } from '../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import { openUrl } from '../../util/openUrl';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { captureControlledSwipe } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import { getTelegramTipsChannelUrl } from '../../util/url';
import {
  IS_BIOMETRIC_AUTH_SUPPORTED,
  IS_DAPP_SUPPORTED,
  IS_ELECTRON,
  IS_IOS_APP,
  IS_TOUCH_ENV,
  IS_WEB,
} from '../../util/windowEnvironment';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useFlag from '../../hooks/useFlag';
import useHideBottomBar from '../../hooks/useHideBottomBar';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import { useStateRef } from '../../hooks/useStateRef';

import LedgerConnect from '../ledger/LedgerConnect';
import LedgerSelectWallets from '../ledger/LedgerSelectWallets';
import LogOutModal from '../main/modals/LogOutModal';
import Switcher from '../ui/Switcher';
import Transition from '../ui/Transition';
import Biometrics from './biometrics/Biometrics';
import SettingsNativeBiometricsTurnOn from './biometrics/NativeBiometricsTurnOn';
import SettingsAbout from './SettingsAbout';
import SettingsAppearance from './SettingsAppearance';
import SettingsAssets from './SettingsAssets';
import SettingsDapps from './SettingsDapps';
import SettingsDeveloperOptions from './SettingsDeveloperOptions';
import SettingsDisclaimer from './SettingsDisclaimer';
import SettingsHeader from './SettingsHeader';
import SettingsHiddenNfts from './SettingsHiddenNfts';
import SettingsLanguage from './SettingsLanguage';
import SettingsPushNotifications from './SettingsPushNotifications';
import SettingsSecurity from './SettingsSecurity';
import SettingsTokenList from './SettingsTokenList';
import SettingsWallets from './SettingsWallets';
import SettingsWalletVersion from './SettingsWalletVersion';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Settings.module.scss';

import aboutImg from '../../assets/settings/settings_about.svg';
import appearanceImg from '../../assets/settings/settings_appearance.svg';
import assetsActivityImg from '../../assets/settings/settings_assets-activity.svg';
import connectedDappsImg from '../../assets/settings/settings_connected-dapps.svg';
import disclaimerImg from '../../assets/settings/settings_disclaimer.svg';
import exitImg from '../../assets/settings/settings_exit.svg';
import helpcenterImg from '../../assets/settings/settings_helpcenter.svg';
import installAppImg from '../../assets/settings/settings_install-app.svg';
import installDesktopImg from '../../assets/settings/settings_install-desktop.svg';
import installMobileImg from '../../assets/settings/settings_install-mobile.svg';
import languageImg from '../../assets/settings/settings_language.svg';
import mtwCardsImg from '../../assets/settings/settings_mtw-cards.svg';
import upgradeImg from '../../assets/settings/settings_mytonwallet.svg';
import notifications from '../../assets/settings/settings_notifications.svg';
import securityImg from '../../assets/settings/settings_security.svg';
import supportImg from '../../assets/settings/settings_support.svg';
import tipsImg from '../../assets/settings/settings_tips.svg';
import tonLinksImg from '../../assets/settings/settings_ton-links.svg';
import tonProxyImg from '../../assets/settings/settings_ton-proxy.svg';
import walletVersionImg from '../../assets/settings/settings_wallet-version.svg';

type OwnProps = {
  isActive: boolean;
  isInsideModal?: boolean;
};

type StateProps = {
  settings: GlobalState['settings'];
  dapps: StoredDappConnection[];
  isOpen?: boolean;
  tokens?: UserToken[];
  isPasswordPresent?: boolean;
  currentVersion?: ApiTonWalletVersion;
  versions?: ApiWalletWithVersionInfo[];
  isCopyStorageEnabled?: boolean;
  supportAccountsCount?: number;
  arePushNotificationsAvailable?: boolean;
  isNftBuyingDisabled?: boolean;
  isViewMode: boolean;
};

const AMOUNT_OF_CLICKS_FOR_DEVELOPERS_MODE = 5;
const SUPPORT_ACCOUNTS_COUNT_DEFAULT = 1;

function Settings({
  settings: {
    state,
    theme,
    animationLevel,
    isTestnet,
    langCode,
    isTonProxyEnabled,
    isDeeplinkHookEnabled,
    baseCurrency,
  },
  dapps,
  isActive,
  isOpen = false,
  tokens,
  isInsideModal,
  isPasswordPresent,
  currentVersion,
  versions,
  isCopyStorageEnabled,
  supportAccountsCount = SUPPORT_ACCOUNTS_COUNT_DEFAULT,
  arePushNotificationsAvailable,
  isNftBuyingDisabled,
  isViewMode,
}: OwnProps & StateProps) {
  const {
    setSettingsState,
    closeSettings,
    toggleDeeplinkHook,
    toggleTonProxy,
    getDapps,
    clearIsPinAccepted,
  } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();

  const transitionRef = useRef<HTMLDivElement>();
  const currentWalletRef = useRef<HTMLDivElement>();
  const { renderingKey } = useModalTransitionKeys(state, isOpen);
  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose(isOpen);
  const [clicksAmount, setClicksAmount] = useState<number>(isTestnet ? AMOUNT_OF_CLICKS_FOR_DEVELOPERS_MODE : 0);
  const prevRenderingKeyRef = useStateRef(usePrevious2(renderingKey));

  const [isDeveloperModalOpen, openDeveloperModal, closeDeveloperModal] = useFlag();
  const [withAllWalletVersions, markWithAllWalletVersions] = useFlag();

  const [isLogOutModalOpened, openLogOutModal, closeLogOutModal] = useFlag();
  // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
  const isInitialScreen = renderingKey === SettingsState.Initial;

  const activeLang = useMemo(() => LANG_LIST.find((l) => l.langCode === langCode), [langCode]);

  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const tonToken = useMemo(() => tokens?.find(({ slug }) => slug === TONCOIN.slug), [tokens]);

  const wallets = useMemo(() => {
    return versions
      ?.filter((v) => v.lastTxId || v.version === 'W5' || withAllWalletVersions)
      ?.map((v) => {
        const tonBalance = formatCurrency(toDecimal(v.balance), tonToken?.symbol ?? '');
        const balanceInCurrency = formatCurrency(
          toBig(v.balance).mul(tonToken?.price ?? 0).round(tonToken?.decimals),
          shortBaseSymbol,
        );

        const accountTokens = [tonBalance];

        return {
          address: v.address,
          version: v.version,
          totalBalance: balanceInCurrency,
          tokens: accountTokens,
          isTestnetSubwalletId: v.isTestnetSubwalletId,
        } satisfies Wallet;
      }) ?? [];
  }, [shortBaseSymbol, tonToken, versions, withAllWalletVersions]);

  const { isScrolled, handleScroll: handleContentScroll } = useScrolledState();

  const handleSlideAnimationStop = useLastCallback(() => {
    if (prevRenderingKeyRef.current === SettingsState.NativeBiometricsTurnOn) {
      clearIsPinAccepted();
    }
  });

  const handleCloseSettings = useLastCallback(() => {
    closeSettings(undefined, { forceOnHeavyAnimation: true });
    setSettingsState({ state: SettingsState.Initial });
  });

  useHistoryBack({
    isActive: isActive && isInitialScreen,
    onBack: handleCloseSettings,
    shouldIgnoreForTelegram: isInsideModal,
  });

  useHideBottomBar(isOpen && !isInitialScreen);

  const handlCloseDeveloperModal = useLastCallback(() => {
    closeDeveloperModal();

    if (IS_CORE_WALLET) {
      handleCloseSettings();
    }
  });

  const handleConnectedDappsOpen = useLastCallback(() => {
    getDapps();
    setSettingsState({ state: SettingsState.Dapps });
  });

  function handleAppearanceOpen() {
    setSettingsState({ state: SettingsState.Appearance });
  }

  function handlePushNotificationsOpen() {
    setSettingsState({ state: SettingsState.PushNotifications });
  }

  function handleSecurityOpen() {
    setSettingsState({ state: SettingsState.Security });
  }

  function handleAssetsOpen() {
    setSettingsState({ state: SettingsState.Assets });
  }

  function handleLanguageOpen() {
    setSettingsState({ state: SettingsState.Language });
  }

  function handleAboutOpen() {
    setSettingsState({ state: SettingsState.About });
  }

  function handleDisclaimerOpen() {
    setSettingsState({ state: SettingsState.Disclaimer });
  }

  const handleBackClick = useLastCallback(() => {
    switch (renderingKey as SettingsState) {
      case SettingsState.HiddenNfts:
      case SettingsState.SelectTokenList:
        setSettingsState({ state: SettingsState.Assets });
        break;

      default:
        setSettingsState({ state: SettingsState.Initial });
    }
  });

  const handleBackClickToAssets = useLastCallback(() => {
    setSettingsState({ state: SettingsState.Assets });
  });

  const handleOpenWalletVersion = useLastCallback(() => {
    setSettingsState({ state: SettingsState.WalletVersion });
  });

  const handleDeeplinkHookToggle = useLastCallback(() => {
    toggleDeeplinkHook({ isEnabled: !isDeeplinkHookEnabled });
  });

  const handleTonProxyToggle = useLastCallback(() => {
    toggleTonProxy({ isEnabled: !isTonProxyEnabled });
  });

  function handleClickInstallApp() {
    void openUrl('https://mytonwallet.io/get', { isExternal: true });
  }

  function handleClickInstallOnDesktop() {
    void openUrl('https://mytonwallet.io/get/desktop', { isExternal: true });
  }

  function handleClickInstallOnMobile() {
    void openUrl('https://mytonwallet.io/get/mobile', { isExternal: true });
  }

  const handleLedgerConnected = useLastCallback(() => {
    setSettingsState({ state: SettingsState.LedgerSelectWallets });
  });

  const [isTrayIconEnabled, setIsTrayIconEnabled] = useState(false);
  useEffect(() => {
    void window.electron?.getIsTrayIconEnabled().then(setIsTrayIconEnabled);
  }, []);

  const handleTrayIconEnabledToggle = useLastCallback(() => {
    setIsTrayIconEnabled(!isTrayIconEnabled);
    void window.electron?.setIsTrayIconEnabled(!isTrayIconEnabled);
  });

  const [isAutoUpdateEnabled, setIsAutoUpdateEnabled] = useState(false);
  useEffect(() => {
    void window.electron?.getIsAutoUpdateEnabled().then(setIsAutoUpdateEnabled);
  }, []);

  const handleAutoUpdateEnabledToggle = useLastCallback(() => {
    setIsAutoUpdateEnabled(!isAutoUpdateEnabled);
    void window.electron?.setIsAutoUpdateEnabled(!isAutoUpdateEnabled);
  });

  const handleBackOrCloseAction = useLastCallback(() => {
    if (isInitialScreen) {
      if (isInsideModal) handleCloseSettings();
    } else {
      handleBackClick();
    }
  });

  const handleCloseLogOutModal = useLastCallback((shouldCloseSettings: boolean) => {
    closeLogOutModal();
    if (shouldCloseSettings) {
      handleCloseSettings();
    }
  });

  const handleMultipleClick = () => {
    if (clicksAmount + 1 >= AMOUNT_OF_CLICKS_FOR_DEVELOPERS_MODE) {
      openDeveloperModal();
    } else {
      setClicksAmount(clicksAmount + 1);
    }
  };

  const handleShowAllWalletVersions = useLastCallback(() => {
    markWithAllWalletVersions();
    handlCloseDeveloperModal();
    handleOpenWalletVersion();
  });

  useEffect(
    () => captureEscKeyListener(isInsideModal ? handleBackOrCloseAction : handleBackClick),
    [isInsideModal],
  );

  useEffect(() => {
    if (!IS_TOUCH_ENV) {
      return undefined;
    }

    return captureControlledSwipe(transitionRef.current!, {
      onSwipeRightStart: () => {
        handleBackOrCloseAction();

        disableSwipeToClose();
      },
      onCancel: () => {
        setSettingsState({ state: prevRenderingKeyRef.current! });

        enableSwipeToClose();
      },
    });
  }, [disableSwipeToClose, enableSwipeToClose, prevRenderingKeyRef]);

  function renderHandleDeeplinkButton() {
    return (
      <div className={styles.item} onClick={handleDeeplinkHookToggle}>
        <img className={styles.menuIcon} src={tonLinksImg} alt={lang('Handle ton:// links')} />
        {lang('Handle ton:// links')}

        <Switcher
          className={styles.menuSwitcher}
          label={lang('Handle ton:// links')}
          checked={isDeeplinkHookEnabled}
        />
      </div>
    );
  }

  function renderSettings() {
    return (
      <div className={styles.slide}>
        <SettingsHeader
          isInsideModal={isInsideModal}
          isViewMode={isViewMode}
          isActive={isActive}
          isScrolled={isScrolled}
          currentWalletRef={currentWalletRef}
          onCloseSettings={handleCloseSettings}
          onRemoveClick={openLogOutModal}
        />

        <div
          className={buildClassName(styles.content, 'custom-scroll', styles.withBottomSpace)}
          onScroll={handleContentScroll}
        >
          {IS_CAPACITOR && (
            <SettingsWallets
              currentWalletRef={currentWalletRef}
              onAddAccount={handleCloseSettings}
            />
          )}

          {IS_CORE_WALLET && (
            <div className={styles.block}>
              <div className={styles.item} onClick={handleClickInstallApp}>
                <img className={styles.menuIcon} src={upgradeImg} alt={lang('Upgrade to MyTonWallet')} />
                <span className={styles.itemTitle}>{lang('Upgrade to MyTonWallet')}</span>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
          )}
          {!IS_CORE_WALLET && IS_WEB && (
            <div className={styles.block}>
              <div className={styles.item} onClick={handleClickInstallApp}>
                <img className={styles.menuIcon} src={installAppImg} alt={lang('Install App')} />
                <span className={styles.itemTitle}>{lang('Install App')}</span>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
          )}
          {IS_EXTENSION && (
            <div className={styles.block}>
              {PROXY_HOSTS && (
                <div className={styles.item} onClick={handleTonProxyToggle}>
                  <img className={styles.menuIcon} src={tonProxyImg} alt={lang('TON Proxy')} />
                  <span className={styles.itemTitle}>{lang('TON Proxy')}</span>

                  <Switcher
                    className={styles.menuSwitcher}
                    label={lang('Toggle TON Proxy')}
                    checked={isTonProxyEnabled}
                  />
                </div>
              )}
              {renderHandleDeeplinkButton()}
            </div>
          )}
          {IS_ELECTRON && (
            <div className={styles.block}>
              {renderHandleDeeplinkButton()}
            </div>
          )}

          {!IS_CORE_WALLET && <p className={styles.blockTitle}>{lang('Settings')}</p>}
          <div className={styles.block}>
            <div className={styles.item} onClick={handleAppearanceOpen}>
              <img className={styles.menuIcon} src={appearanceImg} alt={lang('Appearance')} />
              <div className={styles.itemContent}>
                <span className={styles.itemTitle}>{lang('Appearance')}</span>
                <span className={styles.itemSubtitle}>{lang('Night Mode, Palette, Card')}</span>
              </div>

              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
            {isPasswordPresent && (
              <div className={styles.item} onClick={handleSecurityOpen}>
                <img className={styles.menuIcon} src={securityImg} alt={lang('Security')} />
                <div className={styles.itemContent}>
                  <span className={styles.itemTitle}>{lang('Security')}</span>
                  <span className={styles.itemSubtitle}>
                    {lang(getDoesUsePinPad() ? 'Back Up, Passcode, Auto-Lock' : 'Back Up, Password, Auto-Lock')}
                  </span>
                </div>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            )}
            {!SHOULD_SHOW_ALL_ASSETS_AND_ACTIVITY && (
              <div className={styles.item} onClick={handleAssetsOpen}>
                <img className={styles.menuIcon} src={assetsActivityImg} alt={lang('Assets & Activity')} />
                <div className={styles.itemContent}>
                  <span className={styles.itemTitle}>{lang('Assets & Activity')}</span>
                  <span className={styles.itemSubtitle}>{lang('Base Currency, Token Order, Hidden NFTs')}</span>
                </div>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            )}
            {!!versions?.length && (
              <div className={styles.item} onClick={handleOpenWalletVersion}>
                <img className={styles.menuIcon} src={walletVersionImg} alt={lang('Wallet Versions')} />
                <div className={styles.itemContent}>
                  <span className={styles.itemTitle}>{lang('Wallet Versions')}</span>
                  <span className={styles.itemSubtitle}>{lang('Your assets on other contracts')}</span>
                </div>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            )}
            {!IS_CORE_WALLET && IS_DAPP_SUPPORTED && !isViewMode && dapps.length > 0 && (
              <div className={styles.item} onClick={handleConnectedDappsOpen}>
                <img className={styles.menuIcon} src={connectedDappsImg} alt={lang('Apps')} />
                <div className={styles.itemContent}>
                  <span className={styles.itemTitle}>{lang('Apps')}</span>
                  <span className={styles.itemSubtitle}>{lang('$connected_apps', dapps.length)}</span>
                </div>

                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            )}
            <div className={styles.item} onClick={handlePushNotificationsOpen}>
              <img
                className={styles.menuIcon}
                src={notifications}
                alt={arePushNotificationsAvailable ? lang('Notifications') : lang('Sounds')}
              />
              <div className={styles.itemContent}>
                <span className={styles.itemTitle}>
                  {arePushNotificationsAvailable ? lang('Notifications') : lang('Sounds')}
                </span>
                <span className={styles.itemSubtitle}>{lang('Wallets, Sounds')}</span>
              </div>
              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
            {!IS_CORE_WALLET && (
              <div className={styles.item} onClick={handleLanguageOpen}>
                <img className={styles.menuIcon} src={languageImg} alt={lang('Language')} />
                <div className={styles.itemContent}>
                  <span className={styles.itemTitle}>{lang('Language')}</span>
                  <span className={styles.itemSubtitle}>{activeLang?.name}</span>
                </div>
                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            )}
          </div>

          {!IS_CORE_WALLET && <p className={styles.blockTitle}>{lang('Help')}</p>}

          <div className={styles.block}>
            {!IS_CORE_WALLET && (
              <>
                {supportAccountsCount > 0 && (
                  <a
                    href={`https://t.me/${SUPPORT_USERNAME}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={styles.item}
                  >
                    <img className={styles.menuIcon} src={supportImg} alt={lang('Ask a Question')} />
                    <span className={styles.itemTitle}>{lang('Ask a Question')}</span>

                    <div className={styles.itemInfo}>
                      @{SUPPORT_USERNAME}
                      <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                    </div>
                  </a>
                )}
                <a
                  href={getHelpCenterUrl(langCode, 'home')}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={styles.item}
                >
                  <img className={styles.menuIcon} src={helpcenterImg} alt={lang('Help Center')} />
                  <span className={styles.itemTitle}>{lang('Help Center')}</span>

                  <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                </a>
                <a
                  href={getTelegramTipsChannelUrl(langCode)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={styles.item}
                >
                  <img className={styles.menuIcon} src={tipsImg} alt={lang('MyTonWallet Features')} />
                  <span className={styles.itemTitle}>{lang('MyTonWallet Features')}</span>

                  <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                </a>
              </>
            )}
            <div className={styles.item} onClick={handleDisclaimerOpen}>
              <img className={styles.menuIcon} src={disclaimerImg} alt={lang('Use Responsibly')} />
              <span className={styles.itemTitle}>{lang('Use Responsibly')}</span>

              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
          </div>

          {!IS_CORE_WALLET && (
            <>
              <p className={styles.blockTitle}>{lang('About')}</p>
              <div className={styles.block}>
                {!isNftBuyingDisabled && (
                  <a
                    href={MTW_CARDS_WEBSITE}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={styles.item}
                  >
                    <img className={styles.menuIcon} src={mtwCardsImg} alt={lang('MyTonWallet Cards NFT')} />
                    <span className={styles.itemTitle}>{lang('MyTonWallet Cards NFT')}</span>

                    <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                  </a>
                )}
                {IS_EXTENSION && (
                  <div className={styles.item} onClick={handleClickInstallApp}>
                    <img className={styles.menuIcon} src={installAppImg} alt={lang('Install App')} />
                    <span className={styles.itemTitle}>{lang('Install App')}</span>

                    <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                  </div>
                )}
                {IS_CAPACITOR && (
                  <div className={styles.item} onClick={handleClickInstallOnDesktop}>
                    <img className={styles.menuIcon} src={installDesktopImg} alt={lang('Install on Desktop')} />
                    <span className={styles.itemTitle}>{lang('Install on Desktop')}</span>

                    <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                  </div>
                )}
                {IS_ELECTRON && (
                  <div className={styles.item} onClick={handleClickInstallOnMobile}>
                    <img className={styles.menuIcon} src={installMobileImg} alt={lang('Install on Mobile')} />
                    <span className={styles.itemTitle}>{lang('Install on Mobile')}</span>

                    <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                  </div>
                )}
                <div className={styles.item} onClick={handleAboutOpen}>
                  <img className={styles.menuIcon} src={aboutImg} alt="" />
                  <span className={styles.itemTitle}>{lang('About %app_name%', { app_name: APP_NAME })}</span>

                  <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                </div>
              </div>
            </>
          )}

          {!isPortrait && (
            <div className={styles.block}>
              <div className={buildClassName(styles.item, styles.item_red)} onClick={openLogOutModal}>
                <img
                  className={styles.menuIcon}
                  src={exitImg}
                  alt={IS_IOS_APP ? lang('Remove Wallet') : lang('Exit')}
                />
                <span className={styles.itemTitle}>
                  {IS_IOS_APP ? lang('Remove Wallet') : lang('Exit')}
                </span>
                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
          )}

          <div className={styles.version} onClick={IS_EXPLORER ? undefined : handleMultipleClick}>
            {APP_NAME} {APP_VERSION} {APP_ENV_MARKER}
          </div>
        </div>
      </div>
    );
  }

  function renderContent(isSlideActive: boolean, isFrom: boolean, currentKey: SettingsState) {
    switch (currentKey) {
      case SettingsState.Initial:
        return renderSettings();
      case SettingsState.PushNotifications:
        return (
          <SettingsPushNotifications
            isActive={isActive && isSlideActive}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
          />
        );
      case SettingsState.Appearance:
        return (
          <SettingsAppearance
            isActive={isActive && isSlideActive}
            theme={theme}
            animationLevel={animationLevel}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
            isTrayIconEnabled={isTrayIconEnabled}
            onTrayIconEnabledToggle={handleTrayIconEnabledToggle}
          />
        );
      case SettingsState.Assets:
        return (
          <SettingsAssets
            isActive={isActive && isSlideActive}
            isInsideModal={isInsideModal}
            onBack={handleBackClick}
          />
        );
      case SettingsState.Security:
        return (
          <SettingsSecurity
            isActive={isActive && isSlideActive}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
            isAutoUpdateEnabled={isAutoUpdateEnabled}
            onAutoUpdateEnabledToggle={handleAutoUpdateEnabledToggle}
            onSettingsClose={handleCloseSettings}
          />
        );
      case SettingsState.Dapps:
        return (
          <SettingsDapps
            isActive={isActive && isSlideActive}
            dapps={dapps}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
          />
        );
      case SettingsState.Language:
        return (
          <SettingsLanguage
            isActive={isActive && isSlideActive}
            langCode={langCode}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
          />
        );
      case SettingsState.About:
        return (
          <SettingsAbout
            isActive={isActive && isSlideActive}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
            theme={theme}
          />
        );
      case SettingsState.Disclaimer:
        return (
          <SettingsDisclaimer
            isActive={isActive && isSlideActive}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
          />
        );
      case SettingsState.NativeBiometricsTurnOn:
        return (
          <SettingsNativeBiometricsTurnOn
            isActive={isActive && isSlideActive}
            isInsideModal={isInsideModal}
            handleBackClick={handleBackClick}
          />
        );
      case SettingsState.SelectTokenList:
        return (
          <SettingsTokenList
            isActive={isActive && isSlideActive}
            isInsideModal={isInsideModal}
            handleBackClick={handleBackClickToAssets}
          />
        );
      case SettingsState.WalletVersion:
        return (
          <SettingsWalletVersion
            isActive={isActive && isSlideActive}
            currentVersion={currentVersion}
            handleBackClick={handleBackClick}
            isInsideModal={isInsideModal}
            wallets={wallets}
          />
        );
      case SettingsState.LedgerConnectHardware:
        return (
          <div className={styles.slide}>
            <LedgerConnect
              isActive={isActive && isSlideActive}
              isStatic={!isInsideModal}
              className={styles.nestedTransition}
              onBackButtonClick={handleBackClick}
              onConnected={handleLedgerConnected}
              onClose={handleBackOrCloseAction}
            />
          </div>
        );
      case SettingsState.LedgerSelectWallets:
        return (
          <div className={styles.slide}>
            <LedgerSelectWallets
              isActive={isActive && isSlideActive}
              isStatic={!isInsideModal}
              onBackButtonClick={handleBackClick}
              onClose={handleBackOrCloseAction}
            />
          </div>
        );
      case SettingsState.HiddenNfts:
        return (
          <SettingsHiddenNfts
            isActive={isActive && isSlideActive}
            handleBackClick={handleBackClickToAssets}
            isInsideModal={isInsideModal}
          />
        );
    }
  }

  return (
    <div className={styles.wrapper}>
      <Transition
        ref={transitionRef}
        name={resolveSlideTransitionName()}
        className={buildClassName(isInsideModal ? modalStyles.transition : styles.transitionContainer, 'custom-scroll')}
        activeKey={renderingKey}
        slideClassName={buildClassName(isInsideModal && modalStyles.transitionSlide)}
        withSwipeControl
        onStop={getDoesUsePinPad() ? handleSlideAnimationStop : undefined}
      >
        {renderContent}
      </Transition>
      {!IS_EXPLORER && (
        <SettingsDeveloperOptions
          isOpen={isDeveloperModalOpen}
          isTestnet={isTestnet}
          isCopyStorageEnabled={isCopyStorageEnabled}
          onShowAllWalletVersions={handleShowAllWalletVersions}
          onClose={handlCloseDeveloperModal}
        />
      )}
      <LogOutModal isOpen={isLogOutModalOpened} onClose={handleCloseLogOutModal} />
      {IS_BIOMETRIC_AUTH_SUPPORTED && <Biometrics isInsideModal={isInsideModal} />}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const isPasswordPresent = selectIsPasswordPresent(global);
  const { isCopyStorageEnabled, supportAccountsCount = 1, isNftBuyingDisabled } = global.restrictions;

  const { currentVersion, byId: versionsById } = global.walletVersions ?? {};
  const currentAccountId = selectCurrentAccountId(global);
  const versions = versionsById?.[currentAccountId!];
  const { dapps = MEMO_EMPTY_ARRAY } = selectCurrentAccountState(global) || {};

  return {
    settings: global.settings,
    dapps,
    isOpen: global.areSettingsOpen,
    tokens: selectCurrentAccountTokens(global),
    isPasswordPresent,
    currentVersion,
    versions,
    isCopyStorageEnabled,
    supportAccountsCount,
    isNftBuyingDisabled,
    arePushNotificationsAvailable: global.pushNotifications.isAvailable,
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(Settings));
