import type { Wallet } from '@tonconnect/sdk';
import React, { memo, useLayoutEffect, useState } from '../../lib/teact/teact';

import type { ApiCheck } from '../types';

import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import {
  IS_ANDROID,
  IS_ANDROID_APP,
  IS_IOS,
  IS_LINUX,
  IS_MAC_OS,
  IS_OPERA,
  IS_SAFARI,
  IS_WINDOWS,
} from '../../util/windowEnvironment';
import { getSearchParameter } from '../util/searchParams';
import { initTonConnect, tonConnectUi } from '../util/tonConnect';

import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import Transition from '../../components/ui/Transition';
import Check from './Check';
import Forward from './Forward';
import ForwardConfirm from './ForwardConfirm';
import ManageWallet from './ManageWallet';

import styles from './App.module.scss';

enum AppPages {
  Check,
  Forward,
  ForwardConfirm,
  Help,
  ManageWallet,
}

const TRANSITION_KEYS = Object.values(AppPages).length / 2;

function App() {
  const [wallet, setWallet] = useState<Wallet | undefined>();
  const [activeKey, setActiveKey] = useState<AppPages>(
    getSearchParameter('action') === 'wallet'
      ? AppPages.ManageWallet
      : AppPages.Check,
  );
  const [check, setCheck] = useState<ApiCheck>();
  const [isJustSentRequest, markJustSentRequest] = useFlag(false);
  const [address, setAddress] = useState<string>('');
  const [domain, setDomain] = useState<string>();

  useLayoutEffect(applyDocumentClasses, []);

  useEffectOnce(() => {
    return initTonConnect(setWallet);
  });

  const handleConnectClick = useLastCallback(async () => {
    await tonConnectUi.openModal();
  });

  const handleDisconnectClick = useLastCallback(async () => {
    await tonConnectUi.disconnect();
  });

  return (
    <Transition
      name={resolveSlideTransitionName()}
      activeKey={activeKey}
      renderCount={TRANSITION_KEYS}
      shouldCleanup
      cleanupExceptionKey={AppPages.Check}
      className={styles.app}
    >
      {(isActive) => activeKey === AppPages.ManageWallet ? (
        <ManageWallet
          isActive={isActive}
          wallet={wallet}
          onConnectClick={handleConnectClick}
          onDisconnectClick={handleDisconnectClick}
        />
      ) : activeKey === AppPages.Check ? (
        <Check
          isActive={isActive}
          wallet={wallet}
          check={check}
          setCheck={setCheck}
          isJustSentRequest={isJustSentRequest}
          markJustSentRequest={markJustSentRequest}
          onConnectClick={handleConnectClick}
          onDisconnectClick={handleDisconnectClick}
          onForwardClick={() => setActiveKey(AppPages.Forward)}
        />
      ) : activeKey === AppPages.Forward ? (
        <Forward
          isActive={isActive}
          check={check!}
          address={address}
          setAddress={setAddress}
          setDomain={setDomain}
          onForward={() => setActiveKey(AppPages.ForwardConfirm)}
          onBack={() => setActiveKey(AppPages.Check)}
        />
      ) : activeKey === AppPages.ForwardConfirm && (
        <ForwardConfirm
          isActive={isActive}
          check={check!}
          address={address}
          domain={domain}
          markJustSentRequest={markJustSentRequest}
          onConfirm={() => setActiveKey(AppPages.Check)}
          onBack={() => setActiveKey(AppPages.Forward)}
        />
      )}
    </Transition>
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
    if (IS_ANDROID_APP) {
      documentElement.classList.add('is-android-app');
    }
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
