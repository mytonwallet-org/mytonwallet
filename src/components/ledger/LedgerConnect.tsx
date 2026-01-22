import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { Theme } from '../../global/types';
import type { LedgerTransport } from '../../util/ledger/types';
import { HardwareConnectState } from '../../global/types';

import { IS_CAPACITOR } from '../../config';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import { closeLedgerTab } from '../../util/ledger/tab';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { IS_ANDROID, IS_IOS, IS_IOS_APP, IS_LEDGER_EXTENSION_TAB } from '../../util/windowEnvironment';

import useAppTheme from '../../hooks/useAppTheme';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Button from '../ui/Button';
import Dropdown from '../ui/Dropdown';
import Image from '../ui/Image';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';

import settingsStyles from '../settings/Settings.module.scss';
import modalStyles from '../ui/Modal.module.scss';
import styles from './LedgerModal.module.scss';

import ledgerDesktopSrc from '../../assets/ledger/desktop.png';
import ledgerDesktopDarkSrc from '../../assets/ledger/desktop-dark.png';
import ledgerIosSrc from '../../assets/ledger/ios.png';
import ledgerIosDarkSrc from '../../assets/ledger/ios-dark.png';
import ledgerMobileBluetoothSrc from '../../assets/ledger/mobile-bluetooth.png';
import ledgerMobileBluetoothDarkSrc from '../../assets/ledger/mobile-bluetooth-dark.png';
import ledgerMobileUsbSrc from '../../assets/ledger/mobile-usb.png';
import ledgerMobileUsbDarkSrc from '../../assets/ledger/mobile-usb-dark.png';

interface OwnProps {
  isActive: boolean;
  isStatic?: boolean;
  className?: string;
  onConnected: NoneToVoidFunction;
  onBackButtonClick?: NoneToVoidFunction;
  onCancel?: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  state: HardwareConnectState;
  chain: ApiChain;
  isLedgerConnected?: boolean;
  isChainAppConnected?: boolean;
  availableTransports?: LedgerTransport[];
  lastUsedTransport?: LedgerTransport;
  currentTheme: Theme;
}

const NEXT_SLIDE_DELAY = 500;
const TRANSPORT_NAMES: Record<LedgerTransport, string> = {
  usb: 'USB',
  bluetooth: 'Bluetooth',
};

function LedgerConnect({
  isActive,
  isStatic,
  state,
  chain,
  isLedgerConnected,
  isChainAppConnected,
  availableTransports,
  lastUsedTransport,
  currentTheme,
  className,
  onConnected,
  onBackButtonClick,
  onCancel,
  onClose,
}: OwnProps & StateProps) {
  const { initializeHardwareWalletModal, initializeHardwareWalletConnection } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const [selectedTransport, setSelectedTransport] = useState<LedgerTransport | undefined>(lastUsedTransport);
  const appTheme = useAppTheme(currentTheme);

  const isLedgerFailed = isLedgerConnected === false;
  const isChainAppFailed = isChainAppConnected === false;
  const isConnected = state === HardwareConnectState.Connected;
  const isConnecting = state === HardwareConnectState.Connecting;
  const isWaitingForRemoteTab = state === HardwareConnectState.WaitingForRemoteTab;
  const title = isConnected ? lang('Ledger Connected!') : lang('Connect Ledger');
  const shouldCloseOnCancel = !onCancel;
  const noCancelButton = Boolean(onBackButtonClick);

  const renderingAvailableTransports = useMemo(() => {
    return (availableTransports || []).map((transport) => ({
      value: transport,
      name: TRANSPORT_NAMES[transport],
    }));
  }, [availableTransports]);
  const {
    shouldRender: shouldRenderAvailableTransports,
    ref: availableTransportsRef,
  } = useShowTransition({
    isOpen: Boolean(renderingAvailableTransports.length > 1 && selectedTransport),
    withShouldRender: true,
  });

  useHistoryBack({
    isActive,
    onBack: onCancel ?? onClose,
  });

  useEffect(() => {
    if (selectedTransport) return;
    if (availableTransports?.length) {
      setSelectedTransport(availableTransports?.[0]);
    } else if (IS_IOS_APP) {
      setSelectedTransport('bluetooth');
    }
  }, [availableTransports, selectedTransport]);

  useEffect(() => {
    if (!isActive) return;

    initializeHardwareWalletModal();
  }, [isActive]);

  useEffectWithPrevDeps(([prevLastUsedTransport]) => {
    if (lastUsedTransport && prevLastUsedTransport !== lastUsedTransport) {
      setSelectedTransport(lastUsedTransport);
    }
  }, [lastUsedTransport]);

  const handleConnected = useLastCallback(() => {
    if (IS_LEDGER_EXTENSION_TAB) {
      return;
    }

    setTimeout(() => onConnected(), NEXT_SLIDE_DELAY);
  });

  useEffect(() => {
    if (isConnected && isActive) {
      handleConnected();
    }
  }, [isConnected, isActive, handleConnected]);

  const handleCloseWithRemoteTab = useLastCallback(() => {
    const closeAction = shouldCloseOnCancel ? onClose : onCancel;
    closeLedgerTab(); // To close the remote extension tab when the connection is cancelled in the popup
    closeAction();
  });

  const handleSubmit = useLastCallback(() => {
    if (selectedTransport) {
      initializeHardwareWalletConnection({ transport: selectedTransport });
    }
  });

  function renderAvailableTransports() {
    return (
      <div ref={availableTransportsRef} className={styles.dropdownBlock}>
        <Dropdown
          label={lang('Connection Type')}
          items={renderingAvailableTransports}
          selectedValue={selectedTransport}
          theme="light"
          arrow="chevron"
          disabled={isConnecting}
          className={buildClassName(styles.item, styles.item_small)}
          onChange={setSelectedTransport}
        />
      </div>
    );
  }

  function renderButtons() {
    const isFailed = state === HardwareConnectState.Failed;

    if (IS_LEDGER_EXTENSION_TAB && isConnected) {
      return (
        <div className={buildClassName(styles.actionBlock, isConnected && styles.actionBlockSingle)}>
          <Button
            isDisabled={isConnecting}
            className={buildClassName(styles.button, isConnected && styles.buttonSingle)}
            onClick={onClose}
          >
            {lang('Continue')}
          </Button>
        </div>
      );
    }

    return (
      <div className={buildClassName(
        styles.actionBlock,
        noCancelButton ? styles.actionBlockVertical : styles.actionBlockHorizontal,
        isStatic && styles.actionBlockStatic,
      )}
      >
        <Button
          isPrimary
          isLoading={isConnecting}
          isDisabled={isConnecting || isConnected || !availableTransports?.length}
          className={buildClassName(styles.button, noCancelButton && styles.buttonFullWidth)}
          onClick={handleSubmit}
        >
          {isFailed ? lang('Try Again') : lang('Continue')}
        </Button>
        {!noCancelButton && (
          <Button
            className={buildClassName(styles.button, noCancelButton && styles.buttonFullWidth)}
            onClick={shouldCloseOnCancel ? onClose : onCancel}
          >
            {lang(shouldCloseOnCancel ? 'Cancel' : 'Back')}
          </Button>
        )}
      </div>
    );
  }

  function getLedgerIconSrc() {
    const isDarkTheme = appTheme === 'dark';
    const iconData = {
      desktop: isDarkTheme ? ledgerDesktopDarkSrc : ledgerDesktopSrc,
      mobileUsb: isDarkTheme ? ledgerMobileUsbDarkSrc : ledgerMobileUsbSrc,
      ios: isDarkTheme ? ledgerIosDarkSrc : ledgerIosSrc,
      mobileBluetooth: isDarkTheme ? ledgerMobileBluetoothDarkSrc : ledgerMobileBluetoothSrc,
    };

    if (!IS_CAPACITOR) {
      // Ledger is only supported on iOS for Capacitor app
      return IS_ANDROID ? iconData.mobileUsb : iconData.desktop;
    }

    if (IS_IOS) {
      return iconData.ios;
    }

    return selectedTransport === 'bluetooth' ? iconData.mobileBluetooth : iconData.mobileUsb;
  }

  function renderScreen(handleClose: NoneToVoidFunction, children: TeactNode) {
    return (
      <>
        {!isStatic ? (
          <ModalHeader
            title={title}
            onBackButtonClick={onBackButtonClick}
            onClose={handleClose}
          />
        ) : (
          <div className={settingsStyles.header}>
            <Button isSimple isText onClick={handleClose} className={settingsStyles.headerBack}>
              <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
              <span>{lang('Back')}</span>
            </Button>
            <span className={settingsStyles.headerTitle}>{title}</span>
          </div>
        )}
        <div
          className={buildClassName(
            styles.container, isStatic && styles.containerStatic, isStatic && 'static-container',
          )}
        >
          <Transition
            activeKey={!IS_CAPACITOR ? 0 : (selectedTransport !== 'bluetooth' ? 1 : 2)}
            name="semiFade"
            className={buildClassName(styles.iconBlock, (isPortrait || IS_IOS) && styles.mobile)}
            slideClassName={isStatic ? styles.iconBlockSlideStatic : styles.iconBlockSlide}
          >
            <Image
              url={getLedgerIconSrc()}
              imageClassName={styles.ledgerIcon}
            />
          </Transition>
          {children}
        </div>
      </>
    );
  }

  function renderWaitingForRemoteTab() {
    return renderScreen(handleCloseWithRemoteTab, (
      <>
        <div
          className={buildClassName(
            styles.textBlock,
            styles.textBlock_gap,
          )}
        >
          <span className={styles.text}>
            <i className={buildClassName(styles.textIcon, 'icon-dot')} aria-hidden />
            {lang('Switch to the newly opened tab to connect Ledger.')}
          </span>
          <span className={styles.text}>
            <i className={buildClassName(styles.textIcon, 'icon-dot')} aria-hidden />
            {lang('Once connected, switch back to this window to proceed.')}
          </span>
        </div>
        <div className={buildClassName(styles.actionBlock, styles.actionBlockSingle)}>
          <Button
            className={buildClassName(styles.button, styles.button_single)}
            onClick={handleCloseWithRemoteTab}
          >
            {lang(shouldCloseOnCancel ? 'Cancel' : 'Back')}
          </Button>
        </div>
      </>
    ));
  }

  function renderConnect() {
    return renderScreen(onClose, (
      <>
        <div
          className={buildClassName(
            styles.textBlock,
            isConnected && styles.textBlock_success,
          )}
        >
          <span
            className={buildClassName(
              styles.text,
              isLedgerFailed && styles.text_failed,
              isLedgerConnected && styles.text_connected,
              isConnected && styles.text_success,
            )}
          >
            <i
              className={buildClassName(styles.textIcon, isLedgerConnected ? 'icon-accept' : 'icon-dot')}
              aria-hidden
            />
            {lang('Connect your Ledger')}
          </span>
          <span
            className={buildClassName(
              styles.text,
              isChainAppFailed && styles.text_failed,
              isChainAppConnected && styles.text_connected,
              isConnected && styles.text_success,
            )}
          >
            <i
              className={buildClassName(styles.textIcon, isChainAppConnected ? 'icon-accept' : 'icon-dot')}
              aria-hidden
            />
            {lang('Unlock it and open the %chain% App', { chain: getChainTitle(chain) })}
          </span>
        </div>

        {shouldRenderAvailableTransports && renderAvailableTransports()}
        {renderButtons()}
      </>
    ));
  }

  function renderContent() {
    if (isWaitingForRemoteTab) {
      return renderWaitingForRemoteTab();
    }

    return renderConnect();
  }

  return (
    <Transition
      name={resolveSlideTransitionName()}
      className={buildClassName(modalStyles.transition, 'custom-scroll', className)}
      slideClassName={modalStyles.transitionSlide}
      activeKey={isWaitingForRemoteTab ? 1 : 0}
    >
      {renderContent}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    hardwareState,
    chain,
    isLedgerConnected,
    isChainAppConnected,
    availableTransports,
    lastUsedTransport,
  } = global.hardware;

  return {
    state: hardwareState,
    chain,
    isLedgerConnected,
    isChainAppConnected,
    availableTransports,
    lastUsedTransport,
    currentTheme: global.settings.theme,
  };
})(LedgerConnect));
