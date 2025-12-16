import type { LedgerTransport } from '../../../util/ledger/types';
import type { ErrorTransferResult } from '../../helpers/transfer';
import { ApiHardwareError } from '../../../api/types';
import { AppState, HardwareConnectState } from '../../types';

import { IS_CAPACITOR, IS_EXTENSION } from '../../../config';
import { mergeSortedArrays } from '../../../util/iteratees';
import { closeThisTab, onLedgerTabClose, openLedgerTab } from '../../../util/ledger/tab';
import { pause } from '../../../util/schedulers';
import { IS_LEDGER_EXTENSION_TAB } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import { isErrorTransferResult } from '../../helpers/transfer';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { resetHardware, updateHardware } from '../../reducers';
import { selectCurrentNetwork } from '../../selectors';

// There is no long-term Ledger connection state in the application. Every time the application needs to interact with
// a Ledger device, it ensures the device is connected using the <LedgerConnect> component, and communicates with the
// device immediately after that.

const OPEN_LEDGER_TAB_DELAY = 500;
const LEDGER_WALLET_LOAD_COLUMNS = 3;
const LEDGER_WALLET_LOAD_ROWS = 2;

addActionHandler('initLedgerPage', (global) => {
  return { ...global, appState: AppState.Ledger };
});

addActionHandler('initializeHardwareWalletModal', async (global, actions) => {
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
      actions.showToast({
        message: 'Ledger is not supported on this device.',
      });
    }
  } else if (availableTransports.length === 1) {
    setGlobal(global);

    // Chrome requires a user gesture before showing the WebHID permission dialog in extension tabs.
    if (!IS_LEDGER_EXTENSION_TAB) {
      actions.initializeHardwareWalletConnection({ transport: availableTransports[0] });
    }
  } else {
    if (!hasUsbDevice) {
      global = updateHardware(global, { lastUsedTransport: 'bluetooth' });
    }
    setGlobal(global);
  }
});

addActionHandler('initializeHardwareWalletConnection', async (global, actions, { transport }) => {
  const maxDeviceConnectAttempts = 2;

  for (let attempt = 0; attempt < maxDeviceConnectAttempts; attempt++) {
    const mayRetry = attempt < maxDeviceConnectAttempts - 1;

    setGlobal(updateHardware(getGlobal(), {
      hardwareState: HardwareConnectState.Connecting,
      hardwareWallets: undefined,
      isLedgerConnected: undefined,
      isChainAppConnected: undefined,
    }));

    // Step 1: Connect to the Ledger device

    let isLedgerConnected = await connectLedgerDevice(transport);

    if (!isLedgerConnected && IS_EXTENSION && !IS_LEDGER_EXTENSION_TAB) {
      await spawnLedgerConnectRemoteTab();
      isLedgerConnected = await connectLedgerDevice(transport);
    }

    if (!isLedgerConnected) return;

    // The only thing needed from the remote tab is getting the user permission to use the HID device (see the
    // `openLedgerTab` description for more details). Successful connection means that the permission is granted.
    if (IS_LEDGER_EXTENSION_TAB) {
      return closeThisTab();
    }

    // Step 2: Ensure that the chain app is open on the Ledger device

    const isChainAppConnected = await ensureChainAppOpen(mayRetry);
    if (isChainAppConnected === 'reconnect') continue;
    if (!isChainAppConnected) return;

    // Step 3: Load wallets from the Ledger device

    if (getGlobal().hardware.shouldLoadWallets) {
      const areWalletsLoaded = await loadLedgerWallets(mayRetry);
      if (areWalletsLoaded === 'reconnect') continue;
      if (!areWalletsLoaded) return;
    }

    setGlobal(updateHardware(getGlobal(), {
      hardwareState: HardwareConnectState.Connected,
    }));
    return;
  }
});

async function connectLedgerDevice(transport: LedgerTransport): Promise<boolean> {
  const ledgerApi = await import('../../../util/ledger');
  const isLedgerConnected = await ledgerApi.connectLedger(transport);
  let global = getGlobal();

  if (!isLedgerConnected) {
    global = updateHardware(global, {
      isLedgerConnected: false,
      hardwareState: HardwareConnectState.Failed,
    });

    if (transport === 'usb' && global.hardware.availableTransports?.includes('bluetooth')) {
      global = updateHardware(global, { lastUsedTransport: 'bluetooth' });
    }

    setGlobal(global);
    return false;
  }

  setGlobal(updateHardware(global, {
    isLedgerConnected: true,
    lastUsedTransport: transport,
  }));
  return true;
}

async function ensureChainAppOpen(mayRetry: boolean): Promise<boolean | 'reconnect'> {
  const { chain } = getGlobal().hardware;

  const isChainAppConnected = await callApi('waitForLedgerApp', chain);
  if (isErrorTransferResult(isChainAppConnected)) {
    return handleConnectedLedgerError(isChainAppConnected, mayRetry);
  }

  if (!isChainAppConnected) {
    setGlobal(updateHardware(getGlobal(), {
      isChainAppConnected: false,
      hardwareState: HardwareConnectState.Failed,
    }));
    return false;
  }

  setGlobal(updateHardware(getGlobal(), {
    isChainAppConnected: true,
  }));
  return true;
}

async function spawnLedgerConnectRemoteTab() {
  setGlobal(updateHardware(getGlobal(), {
    hardwareState: HardwareConnectState.WaitingForRemoteTab,
  }));

  await pause(OPEN_LEDGER_TAB_DELAY);
  const id = await openLedgerTab();
  const popup = await chrome.windows.getCurrent();

  await new Promise<void>((resolve) => onLedgerTabClose(id, resolve));
  await chrome.windows.update(popup.id!, { focused: true });
}

async function loadLedgerWallets(mayRetry: boolean): Promise<boolean | 'reconnect'> {
  const global = getGlobal();
  const network = selectCurrentNetwork(global);
  const { chain } = global.hardware;
  const batchSize = LEDGER_WALLET_LOAD_COLUMNS * LEDGER_WALLET_LOAD_ROWS - 1; // Subtract 1 to fit the "Show More" button in a perfect grid

  // We always use 0 as the start index here despite the already imported wallets, because there can be connected
  // another Ledger device which has different wallets.
  const hardwareWallets = await callApi('getLedgerWallets', chain, network, 0, batchSize);
  if (isErrorTransferResult(hardwareWallets)) {
    return handleConnectedLedgerError(hardwareWallets, mayRetry);
  }

  setGlobal(updateHardware(getGlobal(), {
    hardwareWallets,
  }));
  return true;
}

function handleConnectedLedgerError(result: ErrorTransferResult, mayRetry: boolean) {
  const isLedgerDisconnected = result?.error === ApiHardwareError.ConnectionBroken;
  if (isLedgerDisconnected && mayRetry) {
    return 'reconnect';
  }

  setGlobal(updateHardware(getGlobal(), {
    isLedgerConnected: !isLedgerDisconnected,
    ...(isLedgerDisconnected ? { isChainAppConnected: undefined } : undefined),
    hardwareState: HardwareConnectState.Failed,
  }));
  getActions().showError({ error: result?.error });
  return false;
}

addActionHandler('resetHardwareWalletConnect', (global, actions, { chain, shouldLoadWallets }) => {
  return resetHardware(global, chain, shouldLoadWallets);
});

addActionHandler('loadMoreHardwareWallets', async (global, actions) => {
  const network = selectCurrentNetwork(global);
  const { chain, hardwareWallets: oldHardwareWallets = [] } = global.hardware;
  // Set global loading flag
  setGlobal(updateHardware(getGlobal(), { isLoading: true }));
  const lastIndex = oldHardwareWallets[oldHardwareWallets.length - 1]?.wallet.index ?? -1;
  const batchSize = LEDGER_WALLET_LOAD_COLUMNS * LEDGER_WALLET_LOAD_ROWS;

  const hardwareWallets = await callApi('getLedgerWallets', chain, network, lastIndex + 1, batchSize);
  if (isErrorTransferResult(hardwareWallets)) {
    actions.showError({ error: hardwareWallets?.error });
    setGlobal(updateHardware(getGlobal(), { isLoading: undefined }));
    return;
  }

  setGlobal(updateHardware(getGlobal(), {
    hardwareWallets: mergeSortedArrays(
      [oldHardwareWallets, hardwareWallets],
      (w1, w2) => w1.wallet.index - w2.wallet.index,
      true,
    ),
    isLoading: undefined,
  }));
});
