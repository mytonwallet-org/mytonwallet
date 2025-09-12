import type { LedgerTransport } from '../../../util/ledger/types';
import { AppState, HardwareConnectState } from '../../types';

import { IS_CAPACITOR, IS_EXTENSION } from '../../../config';
import { closeThisTab, onLedgerTabClose, openLedgerTab } from '../../../util/ledger/tab';
import { isLedgerConnectionBroken } from '../../../util/ledger/utils';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { IS_LEDGER_EXTENSION_TAB } from '../../../util/windowEnvironment';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { resetHardware, updateHardware } from '../../reducers';
import { selectAllHardwareAccounts, selectCurrentNetwork, selectLedgerAccountIndexToImport } from '../../selectors';

// There is no long-term Ledger connection state in the application. Every time the application needs to interact with
// a Ledger device, it ensures the device is connected using the <LedgerConnect> component, and communicates with the
// device immediately after that.

interface ConnectLedgerOptions {
  transport: LedgerTransport;
  doLoadWallets?: boolean;
  noRetry?: boolean;
  noRemoteTab?: boolean;
}

const OPEN_LEDGER_TAB_DELAY = 500;

addActionHandler('initLedgerPage', (global) => {
  return { ...global, appState: AppState.Ledger };
});

addActionHandler('openHardwareWalletModal', (global) => {
  global = resetHardware(global);

  return { ...global, isHardwareModalOpen: true };
});

addActionHandler('closeHardwareWalletModal', (global) => {
  return { ...global, isHardwareModalOpen: false };
});

addActionHandler('initializeHardwareWalletModal', async (global, actions, { doLoadWallets } = {}) => {
  const ledgerApi = await import('../../../util/ledger');
  const {
    isBluetoothAvailable,
    isUsbAvailable,
  } = await ledgerApi.detectAvailableTransports();
  const hasUsbDevice = await ledgerApi.hasUsbDevice();
  const availableTransports: LedgerTransport[] = [];
  if (isUsbAvailable) {
    availableTransports.push('usb');
  }
  if (isBluetoothAvailable) {
    availableTransports.push('bluetooth');
  }

  global = getGlobal();
  global = updateHardware(global, { availableTransports });

  if (availableTransports.length === 0) {
    setGlobal(global);
    if (IS_CAPACITOR) {
      actions.showDialog({
        title: 'Bluetooth unavailable',
        message: '$bluetooth_enable_guide',
        buttons: {
          confirm: { title: 'Open Settings', action: 'openBluetoothSettings' },
          cancel: { title: 'Cancel' },
        },
      });
    } else {
      actions.showNotification({
        message: 'Ledger is not supported on this device.',
      });
    }
  } else if (availableTransports.length === 1) {
    setGlobal(global);

    // Chrome requires a user gesture before showing the WebHID permission dialog in extension tabs.
    if (!IS_LEDGER_EXTENSION_TAB) {
      actions.initializeHardwareWalletConnection({ transport: availableTransports[0], doLoadWallets });
    }
  } else {
    if (!hasUsbDevice) {
      global = updateHardware(global, { lastUsedTransport: 'bluetooth' });
    }
    setGlobal(global);
  }
});

addActionHandler('initializeHardwareWalletConnection', async (global, actions, options) => {
  await connectLedger(options);
});

async function connectLedger(options: ConnectLedgerOptions) {
  const { transport, doLoadWallets, noRetry, noRemoteTab } = options;
  let global = getGlobal();

  setGlobal(updateHardware(global, {
    hardwareState: HardwareConnectState.Connecting,
    hardwareWallets: undefined,
    isLedgerConnected: undefined,
    isTonAppConnected: undefined,
  }));

  const ledgerApi = await import('../../../util/ledger');
  const isLedgerConnected = await ledgerApi.connectLedger(transport);
  global = getGlobal();

  if (!isLedgerConnected) {
    if (IS_EXTENSION && !IS_LEDGER_EXTENSION_TAB && !noRemoteTab) {
      return connectLedgerViaRemoteTab(options);
    }

    global = updateHardware(global, {
      isLedgerConnected: false,
      hardwareState: HardwareConnectState.Failed,
    });

    if (transport === 'usb' && global.hardware.availableTransports?.includes('bluetooth')) {
      global = updateHardware(global, { lastUsedTransport: 'bluetooth' });
    }

    setGlobal(global);
    return;
  }

  setGlobal(updateHardware(global, {
    isLedgerConnected: true,
  }));

  // The only thing needed from the remote tab is getting the user permission to use the HID device (see the
  // `openLedgerTab` description for more details). Successful connection means that the permission is granted.
  if (IS_LEDGER_EXTENSION_TAB) {
    return closeThisTab();
  }

  try {
    const isTonAppConnected = await ledgerApi.waitLedgerTonApp();
    global = getGlobal();

    if (!isTonAppConnected) {
      setGlobal(updateHardware(global, {
        isTonAppConnected: false,
        hardwareState: HardwareConnectState.Failed,
      }));
      return;
    }

    setGlobal(updateHardware(global, {
      isTonAppConnected: true,
    }));

    const hardwareWallets = doLoadWallets ? await getLedgerWallets(ledgerApi) : [];

    setGlobal(updateHardware(getGlobal(), {
      hardwareWallets,
      hardwareState: HardwareConnectState.Connected,
      lastUsedTransport: transport,
    }));
  } catch (err: any) {
    const isLedgerDisconnected = isLedgerConnectionBroken(err.name);

    if (isLedgerDisconnected && !noRetry) {
      return connectLedger({ ...options, noRetry: true });
    }

    global = getGlobal();
    setGlobal(updateHardware(global, {
      isLedgerConnected: !isLedgerDisconnected,
      isTonAppConnected: isLedgerDisconnected ? undefined : global.hardware.isTonAppConnected,
      hardwareState: HardwareConnectState.Failed,
    }));

    logDebugError('connectHardwareWallet', err);
  }
}

async function connectLedgerViaRemoteTab(options: ConnectLedgerOptions) {
  setGlobal(updateHardware(getGlobal(), {
    hardwareState: HardwareConnectState.WaitingForRemoteTab,
  }));

  await pause(OPEN_LEDGER_TAB_DELAY);
  const id = await openLedgerTab();
  const popup = await chrome.windows.getCurrent();

  await new Promise<void>((resolve) => onLedgerTabClose(id, resolve));
  await chrome.windows.update(popup.id!, { focused: true });
  await connectLedger({ ...options, noRetry: false, noRemoteTab: true });
}

async function getLedgerWallets(ledgerApi: typeof import('../../../util/ledger')) {
  const global = getGlobal();
  const network = selectCurrentNetwork(global);
  const lastIndex = selectLedgerAccountIndexToImport(global, network);
  const currentHardwareAddresses = selectAllHardwareAccounts(global, network)
    .map((account) => account.byChain.ton?.address)
    .filter(Boolean);
  const hardwareWallets = await ledgerApi.getNextLedgerWallets(
    network,
    lastIndex,
    currentHardwareAddresses,
  );

  if ('error' in hardwareWallets) {
    getActions().showError({ error: hardwareWallets.error });
    throw Error(hardwareWallets.error);
  }

  return hardwareWallets;
}

addActionHandler('resetHardwareWalletConnect', (global) => {
  return resetHardware(global);
});

addActionHandler('loadMoreHardwareWallets', async (global, actions, { lastIndex }) => {
  const network = selectCurrentNetwork(global);
  const oldHardwareWallets = global.hardware.hardwareWallets ?? [];
  const ledgerApi = await import('../../../util/ledger');
  const hardwareWallets = await ledgerApi.getNextLedgerWallets(network, lastIndex);

  global = getGlobal();

  if ('error' in hardwareWallets) {
    actions.showError({ error: hardwareWallets.error });
    throw Error(hardwareWallets.error);
  }

  global = updateHardware(global, {
    hardwareWallets: oldHardwareWallets.concat(hardwareWallets),
  });
  setGlobal(global);
});
