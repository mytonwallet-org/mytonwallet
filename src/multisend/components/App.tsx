import type { Wallet, WalletInfo } from '@tonconnect/sdk';
import React, { memo, useEffect, useLayoutEffect, useState } from '../../lib/teact/teact';

import type { TransferRow } from '../types';

import buildClassName from '../../util/buildClassName';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import {
  IS_ANDROID,
  IS_IOS,
  IS_LINUX,
  IS_MAC_OS,
  IS_OPERA,
  IS_SAFARI,
  IS_WINDOWS,
} from '../../util/windowEnvironment';
import { handleTonConnectButtonClick, initTonConnect, tonConnect } from '../utils/tonConnect';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectOnce from '../../hooks/useEffectOnce';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';

import Transition from '../../components/ui/Transition';
import DropPage from './DropPage';
import LoadingPage from './LoadingPage';
import ManageTransferPage from './ManageTransferPage';
import TransferListPage from './TransferListPage';

import styles from './App.module.scss';

type OwnProps = {
  mwWalletInfo?: WalletInfo;
};

enum PageKey {
  Loading,
  Drop,
  TransferList,
  ManageTransfer,
}

function App({ mwWalletInfo }: OwnProps) {
  const [wallet, setWallet] = useState<Wallet | undefined>();
  const [isLoading, setIsLoading] = useState(true);
  const [renderKey, setRenderKey] = useState<PageKey>(PageKey.Loading);
  const [transferData, setTransferData] = useState<TransferRow[]>([]);
  const [editingTransfer, setEditingTransfer] = useState<TransferRow | undefined>();
  const [editingIndex, setEditingIndex] = useState<number | undefined>();
  const { isPortrait } = useDeviceScreen();

  useLayoutEffect(applyDocumentClasses, []);

  useEffectOnce(() => {
    return initTonConnect(setIsLoading, setWallet);
  });

  useEffect(() => {
    if (isLoading) {
      setRenderKey(PageKey.Loading);
    } else {
      setRenderKey(PageKey.Drop);
    }
  }, [isLoading, wallet]);

  const handleConnectClick = useLastCallback(() => {
    if (mwWalletInfo) {
      void handleTonConnectButtonClick(mwWalletInfo);
    }
  });

  const handleDisconnectClick = useLastCallback(
    async () => {
      try {
        await tonConnect.disconnect();
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('Failed to disconnect:', err);
      }
    },
  );

  const handleAddTransferClick = useLastCallback(() => {
    if (!wallet) {
      handleConnectClick();
      return;
    }
    setEditingTransfer(undefined);
    setEditingIndex(undefined);
    setRenderKey(PageKey.ManageTransfer);
  });

  const handleEditTransferClick = useLastCallback((transfer: TransferRow, index: number) => {
    setEditingTransfer(transfer);
    setEditingIndex(index);
    setRenderKey(PageKey.ManageTransfer);
  });

  const handleNavigateToTransferList = useLastCallback(() => {
    setRenderKey(PageKey.TransferList);
  });

  const handleBackToHome = useLastCallback(() => {
    setRenderKey(PageKey.Drop);
  });

  const handleManageTransferBack = useLastCallback(() => {
    setEditingTransfer(undefined);
    setEditingIndex(undefined);
    setRenderKey(transferData.length > 0 ? PageKey.TransferList : PageKey.Drop);
  });

  const handleManageTransferDelete = useLastCallback((index: number) => {
    setTransferData((prevData) => {
      const newData = [...prevData];
      newData.splice(index, 1);

      // Navigate to home if no transfers left, otherwise stay on transfer list
      setRenderKey(newData.length > 0 ? PageKey.TransferList : PageKey.Drop);

      return newData;
    });

    setEditingTransfer(undefined);
    setEditingIndex(undefined);
  });

  const handleManageTransferSubmit = useLastCallback((transfer: TransferRow, index?: number) => {
    if (index !== undefined) {
      setTransferData((prevData) => {
        const newData = [...prevData];
        newData[index] = transfer;
        return newData;
      });
    } else {
      setTransferData((prevData) => [...prevData, transfer]);
    }

    setEditingTransfer(undefined);
    setEditingIndex(undefined);
    setRenderKey(PageKey.TransferList);
  });

  function renderPage(isActive: boolean) {
    switch (renderKey) {
      case PageKey.Drop:
        return (
          <DropPage
            wallet={wallet}
            onConnectClick={handleConnectClick}
            onDisconnectClick={handleDisconnectClick}
            onAddTransferClick={handleAddTransferClick}
            onSetCsvData={setTransferData}
            onNavigateToTransferList={handleNavigateToTransferList}
            isActive={isActive}
          />
        );
      case PageKey.ManageTransfer:
        return (
          <ManageTransferPage
            isActive={isActive}
            editingTransfer={editingTransfer}
            editingIndex={editingIndex}
            onBack={handleManageTransferBack}
            onSubmit={handleManageTransferSubmit}
            onDelete={handleManageTransferDelete}
          />
        );
      case PageKey.TransferList:
        return (
          <TransferListPage
            isActive={isActive}
            transferData={transferData}
            onSetTransferData={setTransferData}
            onAddTransferClick={handleAddTransferClick}
            onEditTransferClick={handleEditTransferClick}
            onBack={handleBackToHome}
          />
        );
      default:
        return <LoadingPage />;
    }
  }

  const prevRenderKey = usePrevious2(renderKey);
  const shouldForceFade = renderKey <= PageKey.Drop && (!prevRenderKey || prevRenderKey <= PageKey.Drop);

  return (
    <div className={styles.app}>
      <Transition
        name={isPortrait && !shouldForceFade ? resolveSlideTransitionName() : 'fade'}
        activeKey={renderKey}
        slideClassName={buildClassName(styles.appSlide, 'custom-scroll')}
      >
        {renderPage}
      </Transition>
    </div>
  );
}

export default memo(App);

function applyDocumentClasses() {
  const { documentElement } = document;

  documentElement.classList.add('is-rendered');

  if (IS_IOS) {
    documentElement.classList.add('is-ios', 'is-mobile');
  } else if (IS_ANDROID) {
    documentElement.classList.add('is-android', 'is-mobile');
  } else if (IS_MAC_OS) {
    documentElement.classList.add('is-macos');
  } else if (IS_WINDOWS) {
    documentElement.classList.add('is-windows');
  } else if (IS_LINUX) {
    documentElement.classList.add('is-linux');
  }
  if (IS_SAFARI) {
    documentElement.classList.add('is-safari');
  }
  if (IS_OPERA) {
    documentElement.classList.add('is-opera');
  }
}
