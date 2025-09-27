import { getActions, getGlobal } from '../../global';

import type { ActionPayloads, GlobalState } from '../../global/types';
import type { OpenUrlOptions } from '../openUrl';
import { ActiveTab, ContentTab } from '../../global/types';

import {
  DEFAULT_CEX_SWAP_SECOND_TOKEN_SLUG,
  DEFAULT_SWAP_SECOND_TOKEN_SLUG,
  GIVEAWAY_CHECKIN_URL,
  IS_CAPACITOR,
  TONCOIN,
} from '../../config';
import {
  selectAccountTokenBySlug,
  selectCurrentAccountNftByAddress,
  selectIsHardwareAccount,
  selectTokenByMinterAddress,
} from '../../global/selectors';
import { callApi } from '../../api';
import { switchToAir } from '../capacitor';
import { isValidAddressOrDomain } from '../isValidAddressOrDomain';
import { omitUndefined } from '../iteratees';
import { logDebug, logDebugError } from '../logs';
import { openUrl } from '../openUrl';
import { waitRender } from '../renderPromise';
import { isTelegramUrl } from '../url';
import {
  CHECKIN_URL,
  SELF_PROTOCOL,
  SELF_UNIVERSAL_URLS,
  TON_PROTOCOL,
  TONCONNECT_PROTOCOL,
  TONCONNECT_PROTOCOL_SELF,
  TONCONNECT_UNIVERSAL_URL,
} from './constants';

import { getIsLandscape, getIsPortrait } from '../../hooks/useDeviceScreen';

enum DeeplinkCommand {
  Air = 'air',
  CheckinWithR = 'r',
  Swap = 'swap',
  BuyWithCrypto = 'buy-with-crypto',
  BuyWithCard = 'buy-with-card',
  Stake = 'stake',
  Giveaway = 'giveaway',
  Transfer = 'transfer',
  Explore = 'explore',
  Receive = 'receive',
}

let urlAfterSignIn: string | undefined;

export function processDeeplinkAfterSignIn() {
  if (!urlAfterSignIn) return;

  void processDeeplink(urlAfterSignIn);

  urlAfterSignIn = undefined;
}

export async function openDeeplinkOrUrl(
  url: string,
  { isFromInAppBrowser, ...urlOptions }: OpenUrlOptions & { isFromInAppBrowser?: boolean },
) {
  if (isTonDeeplink(url) || isTonConnectDeeplink(url) || isSelfDeeplink(url)) {
    await processDeeplink(url, isFromInAppBrowser);
  } else {
    await openUrl(url, urlOptions);
  }
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
export function processDeeplink(url: string, isFromInAppBrowser = false): Promise<boolean> {
  if (!getGlobal().currentAccountId) {
    urlAfterSignIn = url;
  }

  if (isTonConnectDeeplink(url)) {
    return processTonConnectDeeplink(url, isFromInAppBrowser);
  } else if (isSelfDeeplink(url)) {
    return processSelfDeeplink(url);
  } else {
    return processTonDeeplink(url);
  }
}

export function isTonDeeplink(url: string) {
  return url.startsWith(TON_PROTOCOL);
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
async function processTonDeeplink(url: string): Promise<boolean> {
  await waitRender();

  const actions = getActions();
  const global = getGlobal();
  if (!global.currentAccountId) {
    return false;
  }

  // Trying to open the transfer modal from a widget using a deeplink
  if (url === 'ton://transfer') {
    actions.startTransfer({
      isPortrait: getIsPortrait(),
    });

    return true;
  }

  const startTransferParams = parseTonDeeplink(url, global);

  if (!startTransferParams) {
    return false;
  }

  if ('error' in startTransferParams) {
    actions.showError({ error: startTransferParams.error });
    return true;
  }

  actions.startTransfer({
    isPortrait: getIsPortrait(),
    ...startTransferParams,
  });

  if (getIsLandscape()) {
    actions.setLandscapeActionsActiveTabIndex({ index: ActiveTab.Transfer });
  }

  return true;
}

/**
 * Parses a TON deeplink and checks whether the transfer can be initiated.
 * Returns `undefined` if the URL is not a TON deeplink.
 * If there is `error` in the result, there is a problem with the deeplink (the string is to translate via `lang`).
 * Otherwise, returned the parsed transfer parameters.
 */
export function parseTonDeeplink(url: string, global: GlobalState) {
  const params = rawParseTonDeeplink(url);
  if (!params) return undefined;

  if (params.hasUnsupportedParams) {
    return {
      error: '$unsupported_deeplink_parameter',
    };
  }

  const {
    toAddress,
    amount,
    comment,
    binPayload,
    jettonAddress,
    nftAddress,
    stateInit,
    exp,
  } = params;

  const verifiedAddress = isValidAddressOrDomain(toAddress, 'ton') ? toAddress : undefined;

  const transferParams: Omit<NonNullable<ActionPayloads['startTransfer']>, 'isPortrait'> & { error?: string } = {
    toAddress: verifiedAddress,
    tokenSlug: TONCOIN.slug,
    amount,
    comment,
    binPayload,
    stateInit,
  };

  // Check if both text and bin parameters are provided (mutually exclusive)
  if (comment && binPayload) {
    transferParams.error = '$transfer_text_and_bin_exclusive';
  }

  if (jettonAddress) {
    const globalToken = jettonAddress
      ? selectTokenByMinterAddress(global, jettonAddress)
      : undefined;

    if (!globalToken) {
      transferParams.error = '$unknown_token_address';
    } else {
      const accountToken = selectAccountTokenBySlug(global, globalToken.slug);

      if (!accountToken) {
        transferParams.error = '$dont_have_required_token';
      } else {
        transferParams.tokenSlug = globalToken.slug;
      }
    }
  }

  if (nftAddress) {
    const accountNft = selectCurrentAccountNftByAddress(global, nftAddress);

    if (!accountNft) {
      transferParams.error = '$dont_have_required_nft';
    } else {
      transferParams.nfts = [accountNft];
    }
  }

  if (exp && Math.floor(Date.now() / 1000) > exp) {
    transferParams.error = '$transfer_link_expired';
  }

  return omitUndefined(transferParams);
}

function rawParseTonDeeplink(value?: string) {
  if (typeof value !== 'string' || !isTonDeeplink(value) || !value.includes('/transfer/')) {
    return undefined;
  }

  try {
    // In some browsers URL module may handle non-standard protocols incorrectly
    const adaptedDeeplink = value.replace(TON_PROTOCOL, 'https://');
    const url = new URL(adaptedDeeplink);

    const toAddress = url.pathname.replace(/\//g, '');
    const amount = getDeeplinkSearchParam(url, 'amount');
    const comment = getDeeplinkSearchParam(url, 'text');
    const binPayload = getDeeplinkSearchParam(url, 'bin');
    const jettonAddress = getDeeplinkSearchParam(url, 'jetton');
    const nftAddress = getDeeplinkSearchParam(url, 'nft');
    const stateInit = getDeeplinkSearchParam(url, 'init') || getDeeplinkSearchParam(url, 'stateInit');
    const exp = getDeeplinkSearchParam(url, 'exp');

    // Check for unsupported parameters
    const supportedParams = new Set(['amount', 'text', 'bin', 'jetton', 'nft', 'init', 'stateInit', 'exp']);
    const urlParams = Array.from(url.searchParams.keys());
    const hasUnsupportedParams = urlParams.some((param) => !supportedParams.has(param));

    return {
      hasUnsupportedParams,
      toAddress,
      amount: amount ? BigInt(amount) : undefined,
      comment,
      jettonAddress,
      nftAddress,
      binPayload: binPayload ? replaceAllSpacesWithPlus(binPayload) : undefined,
      stateInit: stateInit ? replaceAllSpacesWithPlus(stateInit) : undefined,
      exp: exp ? Number(exp) : undefined,
    };
  } catch (err) {
    return undefined;
  }
}

function isTonConnectDeeplink(url: string) {
  return url.startsWith(TONCONNECT_PROTOCOL)
    || url.startsWith(TONCONNECT_PROTOCOL_SELF)
    || omitProtocol(url).startsWith(omitProtocol(TONCONNECT_UNIVERSAL_URL));
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
async function processTonConnectDeeplink(url: string, isFromInAppBrowser = false): Promise<boolean> {
  if (!isTonConnectDeeplink(url)) {
    return false;
  }

  const { openLoadingOverlay, closeLoadingOverlay } = getActions();

  openLoadingOverlay();

  const returnUrl = await callApi('startSseConnection', {
    url,
    isFromInAppBrowser,
  });

  // Workaround for long network connection initialization in the Capacitor version
  if (returnUrl === 'empty') {
    return true;
  }

  closeLoadingOverlay();

  if (returnUrl) {
    void openUrl(returnUrl, { isExternal: !isFromInAppBrowser });
  }

  return true;
}

export function isSelfDeeplink(url: string) {
  url = forceHttpsProtocol(url);

  return url.startsWith(SELF_PROTOCOL)
    || SELF_UNIVERSAL_URLS.some((u) => url.startsWith(u));
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
export async function processSelfDeeplink(deeplink: string): Promise<boolean> {
  try {
    deeplink = convertSelfDeeplinkToSelfUrl(deeplink);

    const { pathname, searchParams } = new URL(deeplink);
    const command = pathname.split('/').find(Boolean);
    const actions = getActions();
    const global = getGlobal();
    const { isTestnet } = global.settings;
    const isLedger = selectIsHardwareAccount(global);

    logDebug('Processing deeplink', deeplink);

    switch (command) {
      case DeeplinkCommand.Air: {
        if (!IS_CAPACITOR) return false;
        switchToAir();
        return true;
      }

      case DeeplinkCommand.CheckinWithR: {
        const r = pathname.match(/r\/(.*)$/)?.[1];
        const url = `${CHECKIN_URL}${r ? `?r=${r}` : ''}`;
        void openUrl(url);
        return true;
      }

      case DeeplinkCommand.Giveaway: {
        const giveawayId = pathname.match(/giveaway\/([^/]+)/)?.[1];
        const url = `${GIVEAWAY_CHECKIN_URL}${giveawayId ? `?giveawayId=${giveawayId}` : ''}`;
        void openUrl(url);
        return true;
      }

      case DeeplinkCommand.Swap: {
        if (isTestnet) {
          actions.showError({ error: 'Swap is not supported in Testnet.' });
        } else if (isLedger) {
          actions.showError({ error: 'Swap is not yet supported by Ledger.' });
        } else {
          actions.startSwap({
            tokenInSlug: searchParams.get('in') || TONCOIN.slug,
            tokenOutSlug: searchParams.get('out') || DEFAULT_SWAP_SECOND_TOKEN_SLUG,
            amountIn: toNumberOrEmptyString(searchParams.get('amount')) || '10',
          });
        }
        return true;
      }

      case DeeplinkCommand.BuyWithCrypto: {
        if (isTestnet) {
          actions.showError({ error: 'Swap is not supported in Testnet.' });
        } else if (isLedger) {
          actions.showError({ error: 'Swap is not yet supported by Ledger.' });
        } else {
          actions.startSwap({
            tokenInSlug: searchParams.get('in') || DEFAULT_CEX_SWAP_SECOND_TOKEN_SLUG,
            tokenOutSlug: searchParams.get('out') || TONCOIN.slug,
            amountIn: toNumberOrEmptyString(searchParams.get('amount')) || '100',
          });
        }
        return true;
      }

      case DeeplinkCommand.BuyWithCard: {
        if (isTestnet) {
          actions.showError({ error: 'Buying with card is not supported in Testnet.' });
        } else {
          actions.openOnRampWidgetModal({ chain: 'ton' });
        }
        return true;
      }

      case DeeplinkCommand.Stake: {
        if (isTestnet) {
          actions.showError({ error: 'Staking is not supported in Testnet.' });
        } else {
          actions.startStaking();
        }
        return true;
      }

      case DeeplinkCommand.Transfer: {
        return await processTonDeeplink(convertSelfUrlToTonDeeplink(deeplink));
      }

      case DeeplinkCommand.Explore: {
        actions.closeSettings();
        actions.openExplore();
        actions.setActiveContentTab({ tab: ContentTab.Explore });

        const host = pathname.split('/').filter(Boolean)[1];
        if (host) {
          const matchingSite = getGlobal().exploreData?.sites.find(({ url }) => {
            const siteHost = isTelegramUrl(url)
              ? new URL(url).pathname.split('/').filter(Boolean)[0]
              : new URL(url).hostname;

            return siteHost === host;
          });

          if (matchingSite) {
            void openUrl(matchingSite.url);
          }
        }

        return true;
      }

      case DeeplinkCommand.Receive: {
        if (getIsLandscape()) {
          actions.setLandscapeActionsActiveTabIndex({ index: ActiveTab.Receive });
        } else {
          actions.openReceiveModal();
        }
        return true;
      }
    }
  } catch (err) {
    logDebugError('processSelfDeeplink', err);
  }

  return false;
}

/**
 * Parses a deeplink and checks whether the transfer can be initiated.
 * See `parseTonDeeplink` for information about the returned values.
 */
export function parseDeeplinkTransferParams(url: string, global: GlobalState) {
  let tonDeeplink = url;

  if (isSelfDeeplink(url)) {
    try {
      url = convertSelfDeeplinkToSelfUrl(url);
      const { pathname } = new URL(url);
      const command = pathname.split('/').find(Boolean);

      if (command === DeeplinkCommand.Transfer) {
        tonDeeplink = convertSelfUrlToTonDeeplink(url);
      }
    } catch (err) {
      logDebugError('parseDeeplinkTransferParams', err);
    }
  }

  return parseTonDeeplink(tonDeeplink, global);
}

function convertSelfDeeplinkToSelfUrl(deeplink: string) {
  if (deeplink.startsWith(SELF_PROTOCOL)) {
    return deeplink.replace(SELF_PROTOCOL, `${SELF_UNIVERSAL_URLS[0]}/`);
  }
  return deeplink;
}

function convertSelfUrlToTonDeeplink(deeplink: string) {
  deeplink = forceHttpsProtocol(deeplink);

  for (const selfUniversalUrl of SELF_UNIVERSAL_URLS) {
    if (deeplink.startsWith(selfUniversalUrl)) {
      return deeplink.replace(`${selfUniversalUrl}/`, TON_PROTOCOL);
    }
  }

  return deeplink;
}

function omitProtocol(url: string) {
  return url.replace(/^https?:\/\//, '');
}

function forceHttpsProtocol(url: string) {
  return url.replace(/^http:\/\//, 'https://');
}

function toNumberOrEmptyString(input?: string | null) {
  return String(Number(input) || '');
}

function replaceAllSpacesWithPlus(value: string) {
  return value.replace(/ /g, '+');
}

function getDeeplinkSearchParam(url: URL, param: string) {
  return url.searchParams.get(param) ?? undefined;
}
