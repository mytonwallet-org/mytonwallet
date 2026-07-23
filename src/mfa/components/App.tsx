import React, { memo, useLayoutEffect, useState } from '../../lib/teact/teact';

import type { ApiInstallRequest, ApiTransaction } from '../types';

import { getTelegramApp } from '../../util/telegram';
import {
  IS_ANDROID,
  IS_IOS,
  IS_LINUX,
  IS_MAC_OS,
  IS_OPERA,
  IS_SAFARI,
  IS_WINDOWS,
} from '../../util/windowEnvironment';
import { fetchInstallRequest } from '../utils/installRequest';
import { parseMfaStartParam } from '../utils/startParam';
import { fetchTransaction } from '../utils/transaction';

import useEffectOnce from '../../hooks/useEffectOnce';

import Transition from '../../components/ui/Transition';
import Confirmation from './Confirmation';
import Confirmed from './Confirmed';
import InstallConfirmation from './InstallConfirmation';

import styles from './App.module.scss';

enum AppPages {
  CONFIRMATION,
  INSTALL_CONFIRMATION,
  CONFIRMED,
}

const TRANSITION_KEYS = Object.values(AppPages).length / 2;

function App() {
  const startParam = getTelegramApp()?.initDataUnsafe.start_param;
  const parsedStartParam = parseMfaStartParam(startParam);

  const [activeKey, setActiveKey] = useState<AppPages>(
    parsedStartParam.isInstall
      ? AppPages.INSTALL_CONFIRMATION : AppPages.CONFIRMATION,
  );
  const [isLoading, setLoading] = useState<boolean>(true);

  const [transaction, setTransaction] = useState<ApiTransaction | undefined>(undefined);
  const [installRequest, setInstallRequest] = useState<ApiInstallRequest | undefined>(undefined);
  const [requestId, setRequestId] = useState<string | undefined>(undefined);

  useLayoutEffect(applyDocumentClasses, []);

  useEffectOnce(() => {
    if (!parsedStartParam.id) {
      setLoading(false);
      return;
    };

    if (parsedStartParam.isInstall) {
      const { requestId: installRequestId } = parsedStartParam;
      if (!installRequestId) {
        setLoading(false);
        return;
      }

      setRequestId(installRequestId);
      setActiveKey(AppPages.INSTALL_CONFIRMATION);

      fetchInstallRequest(installRequestId).then((result) => {
        setInstallRequest(result);
      }).catch((err) => {
        // eslint-disable-next-line no-console
        console.error(err);
        alert(`ERROR: ${err}`);
      });

      return;
    }

    fetchTransaction(parsedStartParam.id).then((tx) => {
      setTransaction(tx);
      setLoading(false);
    }).catch((err) => {
      // eslint-disable-next-line no-console
      console.error(err);
      alert(`ERROR: ${err}`);
      // setLoading(false);
    });
  });

  const onConfirm = () => {
    setActiveKey(AppPages.CONFIRMED);
  };

  return (
    <div className={styles.root}>
      <Transition
        name="slideFade"
        activeKey={activeKey}
        renderCount={TRANSITION_KEYS}
        shouldCleanup
        cleanupExceptionKey={AppPages.CONFIRMATION}
        className={styles.app}
      >
        {(isActive) => activeKey === AppPages.CONFIRMATION ? (
          <Confirmation
            transaction={transaction}
            requestId={parsedStartParam.id}
            isLoading={isLoading}
            onConfirm={onConfirm}
            isActive={isActive}
          />
        ) : activeKey === AppPages.INSTALL_CONFIRMATION
          ? (
            <InstallConfirmation
              isActive={isActive}
              installRequest={installRequest}
              walletApp={parsedStartParam.walletApp}
              onConfirm={onConfirm}
              reqId={requestId}
            />
          )
          : activeKey === AppPages.CONFIRMED && (
            <Confirmed
              isActive={isActive}
              isTransaction={!!transaction}
              walletApp={parsedStartParam.walletApp}
            />
          )}
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
