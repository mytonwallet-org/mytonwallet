import { Capacitor } from '@capacitor/core';
import type { ActionPerformed, Token } from '@capacitor/push-notifications';
import { PushNotifications } from '@capacitor/push-notifications';
import { getActions, getGlobal, setGlobal } from '../../global';

import type { ApiChain, ApiStakingType } from '../../api/types';
import type { GlobalState } from '../../global/types';

import { TONCOIN } from '../../config';
import { selectAccountIdByAddress } from '../../global/selectors';
import { selectNotificationAddressesSlow } from '../../global/selectors/notifications';
import { callApi } from '../../api';
import { MINUTE } from '../../api/constants';
import { pick } from '../iteratees';
import { logDebugError } from '../logs';
import { getCapacitorPlatform } from './platform';

interface ShowTxMessageData {
  action: 'swap' | 'nativeTx';
  address: string;
  txId: string;
  chain?: ApiChain; // `ton` by default
}

interface StakingMessageData {
  action: 'staking';
  address: string;
  stakingType: ApiStakingType;
  stakingId: string;
  logId: string;
}

interface OpenActivityMessageData {
  action: 'jettonTx';
  address: string;
  slug: string;
  txId: string;
}

interface OpenUrlMessageData {
  action: 'openUrl';
  // The wallet address that should be switched to before opening the URL
  address?: string;
  url: string;
  // For the following parameters, see the `openUrl` options
  isExternal?: boolean;
  title?: string;
  subtitle?: string;
}

interface ExpiringDnsMessageData {
  action: 'expiringDns';
  address: string;
  domain: string;
  domainAddress: string;
  daysUntilExpiration: string;
}

type MessageData = StakingMessageData | OpenActivityMessageData | ShowTxMessageData | OpenUrlMessageData
  | ExpiringDnsMessageData;

let nextUpdatePushNotifications = 0;

export async function initNotificationsWithGlobal(global: GlobalState) {
  const isPushNotificationsAvailable = Capacitor.isPluginAvailable('PushNotifications');

  setGlobal({
    ...global,
    pushNotifications: {
      ...global.pushNotifications,
      isAvailable: isPushNotificationsAvailable,
    },
  });

  if (!isPushNotificationsAvailable) {
    return;
  }

  await PushNotifications.addListener('pushNotificationActionPerformed', handlePushNotificationActionPerformed);

  await PushNotifications.addListener('registration', handlePushNotificationRegistration);

  await PushNotifications.addListener('registrationError', (err) => {
    logDebugError('Registration error: ', err.error);
  });

  let notificationStatus = await PushNotifications.checkPermissions();

  if (notificationStatus.receive === 'prompt-with-rationale' || notificationStatus.receive === 'prompt') {
    notificationStatus = await PushNotifications.requestPermissions();
  }

  if (notificationStatus.receive !== 'granted') {
    // For request iOS returns 'denied', but 'granted' follows immediately without new requests
    return;
  }

  await PushNotifications.register();
}

function handlePushNotificationActionPerformed(notification: ActionPerformed) {
  const {
    showAnyAccountTx,
    openAnyAccountStakingInfo,
    switchAccountAndOpenUrl,
    openDomainRenewalModal,
  } = getActions();
  const global = getGlobal();
  const notificationData = notification.notification.data as MessageData;
  const { action, address } = notificationData;
  const chain = 'chain' in notificationData && notificationData.chain
    ? notificationData.chain
    : TONCOIN.chain;
  const accountId = address === undefined ? undefined : selectAccountIdByAddress(global, chain, address);
  const network = 'mainnet';

  if (action === 'openUrl') {
    switchAccountAndOpenUrl({
      accountId,
      network,
      ...pick(notificationData, ['url', 'isExternal', 'title', 'subtitle']),
    });
    return;
  }

  if (!accountId) return;

  if (action === 'nativeTx' || action === 'swap') {
    const { txId } = notificationData;
    showAnyAccountTx({ accountId, txId, network, chain });
  } else if (action === 'jettonTx') {
    const { txId } = notificationData;
    showAnyAccountTx({ accountId, txId, network, chain });
  } else if (action === 'staking') {
    const { stakingId } = notificationData;
    openAnyAccountStakingInfo({ accountId, network, stakingId });
  } else if (action === 'expiringDns') {
    const { domainAddress } = notificationData;
    openDomainRenewalModal({ accountId, network, addresses: [domainAddress] });
  }
}

function handlePushNotificationRegistration(token: Token) {
  const userToken = token.value;

  getActions().registerNotifications({ userToken, platform: getCapacitorPlatform()! });

  window.addEventListener('focus', async () => {
    const global = getGlobal();
    const notificationAccounts = global.pushNotifications.enabledAccounts;
    if (notificationAccounts.length && nextUpdatePushNotifications <= Date.now()) {
      await callApi('subscribeNotifications', {
        userToken,
        platform: getCapacitorPlatform()!,
        langCode: global.settings.langCode,
        addresses: Object.values(selectNotificationAddressesSlow(global, notificationAccounts)).flat(),
      });
      nextUpdatePushNotifications = Date.now() + (60 * MINUTE);
    }
  }, { capture: true });
}
