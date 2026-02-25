import { Address } from '@ton/core/dist/address/Address';
import { getActions, getGlobal } from '../../global';

import type { ApiChain, ApiNetwork } from '../../api/types';
import type { ActionPayloads, GlobalState } from '../../global/types';
import type { OpenUrlOptions } from '../openUrl';
import { DappProtocolType } from '../../api/dappProtocols/types';
import { ActiveTab, ContentTab } from '../../global/types';

import {
  DEFAULT_SWAP_AMOUNT,
  DEFAULT_SWAP_SECOND_TOKEN_SLUG,
  GIVEAWAY_CHECKIN_URL,
  IS_CAPACITOR,
  IS_EXPLORER,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRX,
} from '../../config';
import {
  selectAccountTokenBySlug,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountNftByAddress,
  selectIsHardwareAccount,
  selectTokenByMinterAddress,
} from '../../global/selectors';
import { callApi } from '../../api';
import { switchToAir } from '../capacitor';
import { getChainConfig, getSupportedChains } from '../chain';
import { fromDecimal } from '../decimals';
import { isValidAddressOrDomain } from '../isValidAddress';
import { omitUndefined } from '../iteratees';
import { logDebug, logDebugError } from '../logs';
import { isSubproject, openUrl } from '../openUrl';
import { waitRender } from '../renderPromise';
import { waitFor } from '../schedulers';
import { isTelegramUrl } from '../url';
import {
  CHECKIN_URL,
  SELF_PROTOCOL,
  SELF_UNIVERSAL_URLS,
  TON_PROTOCOL,
  TONCONNECT_PROTOCOL,
  TONCONNECT_PROTOCOL_SELF,
  TONCONNECT_UNIVERSAL_URL,
  WALLETCONNECT_PROTOCOL,
} from './constants';

import { getIsLandscape, getIsPortrait } from '../../hooks/useDeviceScreen';

export const enum DeeplinkCommand {
  Air = 'air',
  CheckinWithR = 'r',
  Swap = 'swap',
  BuyWithCrypto = 'buy-with-crypto',
  BuyWithCard = 'buy-with-card',
  Offramp = 'offramp',
  Stake = 'stake',
  Giveaway = 'giveaway',
  Transfer = 'transfer',
  Explore = 'explore',
  Receive = 'receive',
  View = 'view',
  Token = 'token',
  Transaction = 'tx',
  Nft = 'nft',
}

const EXPLORER_ALLOWED_COMMANDS = new Set([
  DeeplinkCommand.View,
  DeeplinkCommand.Transaction,
  DeeplinkCommand.Nft,
]);

const OPEN_IN_NATIVE_DELAY_MS = 2000;

let urlAfterSignIn: string | undefined;
let urlAfterInit: string | undefined;

export function processDeeplinkAfterSignIn() {
  if (!urlAfterSignIn) return;

  void processDeeplink(urlAfterSignIn);

  urlAfterSignIn = undefined;
}

export function processDeeplinkAfterInit() {
  if (!urlAfterInit) return;

  const url = urlAfterInit;
  urlAfterInit = undefined;

  void processDeeplink(url);
}

export async function openDeeplinkOrUrl(
  url: string,
  { isFromInAppBrowser, ...urlOptions }: OpenUrlOptions & { isFromInAppBrowser?: boolean } = {},
) {
  if (
    isTonDeeplink(url)
    || isTronDeeplink(url)
    || isTonConnectDeeplink(url)
    || isWalletConnectDeeplink(url)
    || isSelfDeeplink(url)
  ) {
    await processDeeplink(url, isFromInAppBrowser);
  } else {
    await openUrl(url, urlOptions);
  }
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
export function processDeeplink(url: string, isFromInAppBrowser = false): Promise<boolean> {
  const global = getGlobal();

  if ((global as AnyLiteral).isInited === false) {
    urlAfterInit = url;
    return Promise.resolve(true);
  }

  if (!global.currentAccountId) {
    urlAfterSignIn = url;
  }

  const maybeDappProtocol = getDappProtocolForDeeplink(url);

  if (maybeDappProtocol) {
    return processDappConnectorDeeplink(maybeDappProtocol, url, isFromInAppBrowser);
  }

  if (isSelfDeeplink(url)) {
    return processSelfDeeplink(url);
  }

  if (url.startsWith('tether:')) {
    return processTronTetherDeeplink(url);
  }

  if (url.startsWith('tron:')) {
    return processTronDeeplink(url);
  }

  return processTonDeeplink(url);
}

export function getDeeplinkFromLocation(): string | undefined {
  const { pathname, search } = window.location;
  // Remove leading slash from pathname to avoid double slashes in the deeplink
  const normalizedPathname = pathname.startsWith('/') ? pathname.slice(1) : pathname;
  const deeplinkPart = normalizedPathname + search;

  return deeplinkPart ? `${SELF_PROTOCOL}${deeplinkPart}` : undefined;
}

export function tryOpenNativeApp(fallbackUrl: string) {
  const deeplinkUrl = getDeeplinkFromLocation() || SELF_PROTOCOL;
  let pageHidden = false;

  function onHidden() {
    pageHidden = true;
  }

  function onVisibilityChange() {
    if (document.hidden) {
      onHidden();
    }
  }

  // `visibilitychange`: mobile app switch, tab switch, window minimize.
  // `blur`: desktop native app opens on top (tab stays "visible" but window loses focus).
  document.addEventListener('visibilitychange', onVisibilityChange);
  window.addEventListener('blur', onHidden);

  window.location.href = deeplinkUrl;

  window.setTimeout(() => {
    document.removeEventListener('visibilitychange', onVisibilityChange);
    window.removeEventListener('blur', onHidden);

    if (!pageHidden) {
      window.open(fallbackUrl, '_blank');
    }
  }, OPEN_IN_NATIVE_DELAY_MS);
}

export function isTonDeeplink(url: string) {
  return url.startsWith(TON_PROTOCOL);
}

export function isTronDeeplink(url: string) {
  return url.startsWith('tron:') || url.startsWith('tether:');
}

// Generic handler for transfer deeplinks
async function processTransferDeeplink(
  parse: (global: GlobalState) =>
    (Omit<NonNullable<ActionPayloads['startTransfer']>, 'isPortrait'> & { error?: string }) | undefined,
): Promise<boolean> {
  await waitRender();

  const actions = getActions();
  const global = getGlobal();
  const currentAccountId = selectCurrentAccountId(global);
  if (!currentAccountId) return false;

  const startTransferParams = parse(global);

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

async function processTonDeeplink(url: string): Promise<boolean> {
  // Trying to open the transfer modal from a widget using a deeplink
  if (url === 'ton://transfer') {
    const actions = getActions();
    actions.startTransfer({
      isPortrait: getIsPortrait(),
    });

    return true;
  }

  return processTransferDeeplink((global) => parseTonDeeplink(url, global));
}

async function processTronDeeplink(url: string): Promise<boolean> {
  return processTransferDeeplink((global) => parseTronDeeplinkForTrx(url, global));
}

async function processTronTetherDeeplink(url: string): Promise<boolean> {
  return processTransferDeeplink((global) => parseTronTetherDeeplink(url, global));
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

function parseTronDeeplink(
  url: string,
  global: GlobalState,
  getTokenSlug: (global: GlobalState) => string | undefined,
  decimals: number,
) {
  const params = rawParseTronDeeplink(url);
  if (!params) return undefined;

  const {
    toAddress, amount, hasUnsupportedParams,
  } = params;

  const verifiedAddress = isValidAddressOrDomain(toAddress, 'tron') ? toAddress : undefined;
  const tokenSlug = getTokenSlug(global);

  const transferParams: Omit<NonNullable<ActionPayloads['startTransfer']>, 'isPortrait'> & { error?: string } = {
    toAddress: verifiedAddress,
    tokenSlug,
    amount: amount ? fromDecimal(amount, decimals) : undefined,
  };

  if (hasUnsupportedParams) {
    transferParams.error = '$unsupported_deeplink_parameter';
  }

  return omitUndefined(transferParams);
}

function parseTronDeeplinkForTrx(url: string, global: GlobalState) {
  return parseTronDeeplink(url, global, () => TRX.slug, TRX.decimals);
}

function parseTronTetherDeeplink(url: string, global: GlobalState) {
  const { isTestnet } = global.settings;
  const network: ApiNetwork = isTestnet ? 'testnet' : 'mainnet';
  const { usdtSlug } = getChainConfig('tron');
  const getTokenSlug = () => usdtSlug[network];

  return parseTronDeeplink(url, global, getTokenSlug, TRC20_USDT_MAINNET.decimals);
}

function rawParseTronDeeplink(value: string) {
  try {
    const withoutScheme = value.replace(/^(tron|tether):/, '');
    const [addressPart, queryPart] = withoutScheme.split('?');
    const toAddress = addressPart ?? '';

    const searchParams = new URLSearchParams(queryPart ?? '');
    const amount = searchParams.get('amount') ?? undefined;

    const urlParams = Array.from(searchParams.keys());
    const hasUnsupportedParams = urlParams.some((param) => param !== 'amount');

    return {
      toAddress,
      amount,
      hasUnsupportedParams,
    };
  } catch (err) {
    return undefined;
  }
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

function isWalletConnectDeeplink(url: string) {
  return url.startsWith(WALLETCONNECT_PROTOCOL);
}

function getDappProtocolForDeeplink(url: string) {
  switch (true) {
    case isTonConnectDeeplink(url): {
      return DappProtocolType.TonConnect;
    }
    case isWalletConnectDeeplink(url): {
      return DappProtocolType.WalletConnect;
    }
    default:
      return undefined;
  }
}

// Returns `true` if the link has been processed, ideally resulting to a UI action
async function processDappConnectorDeeplink(
  protocol: DappProtocolType,
  url: string,
  isFromInAppBrowser = false,
): Promise<boolean> {
  if (!getDappProtocolForDeeplink(url)) {
    return false;
  }

  const { openLoadingOverlay, closeLoadingOverlay } = getActions();

  openLoadingOverlay();

  const returnUrl = await callApi(`${protocol}_handleDeepLink`,
    url,
    isFromInAppBrowser,
  );

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
    const currentNetwork: ApiNetwork = isTestnet ? 'testnet' : 'mainnet';
    const isLedger = selectIsHardwareAccount(global);

    logDebug('Processing deeplink', deeplink);

    // In explorer mode, only allow `View` and `Transaction` commands
    if (IS_EXPLORER && !EXPLORER_ALLOWED_COMMANDS.has(command as DeeplinkCommand)) {
      actions.showError({ error: 'This command is not supported in explorer mode' });
      return false;
    }

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
            amountIn: toNumberOrEmptyString(searchParams.get('amount')) || DEFAULT_SWAP_AMOUNT,
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
          const { nativeToken, buySwap: defaultBuySwap } = getChainConfig('ton');
          actions.startSwap({
            tokenInSlug: searchParams.get('in') || defaultBuySwap.tokenInSlug,
            tokenOutSlug: searchParams.get('out') || nativeToken.slug,
            amountIn: toNumberOrEmptyString(searchParams.get('amount')) || defaultBuySwap.amountIn,
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

      case DeeplinkCommand.Offramp: {
        const transactionId = searchParams.get('transactionId') ?? undefined;
        const baseCurrencyCode = searchParams.get('baseCurrencyCode') ?? undefined;
        const baseCurrencyAmount = searchParams.get('baseCurrencyAmount') ?? undefined;
        const depositWalletAddress = searchParams.get('depositWalletAddress') ?? undefined;
        const depositWalletAddressTag = searchParams.get('depositWalletAddressTag') ?? undefined;

        logDebug('Processing offramp deeplink', {
          transactionId,
          baseCurrencyCode,
          baseCurrencyAmount,
          depositWalletAddress,
          depositWalletAddressTag,
        });

        if (!depositWalletAddress) {
          actions.showError({ error: '$missing_offramp_deposit_address' });
          return false;
        }

        const mapping = getOfframpTokenMapping(baseCurrencyCode, global);

        if (!mapping) {
          actions.showError({ error: '$unsupported_deeplink_parameter' });
          return false;
        }

        let amount: bigint | undefined;

        if (baseCurrencyAmount) {
          try {
            const tokenInfo = global.tokenInfo.bySlug[mapping.tokenSlug];
            const decimals = tokenInfo?.decimals;

            if (decimals !== undefined) {
              amount = fromDecimal(baseCurrencyAmount, decimals);
            }
          } catch (err) {
            logDebugError('processSelfDeeplinkOfframpAmount', err);
          }
        }

        actions.addSavedAddress({
          address: depositWalletAddress,
          name: 'MoonPay Off-Ramp',
          chain: mapping.chain,
        });

        actions.startTransfer({
          isPortrait: getIsPortrait(),
          tokenSlug: mapping.tokenSlug,
          toAddress: depositWalletAddress,
          comment: depositWalletAddressTag ?? undefined,
          amount,
          isTransferReadonly: true,
          isOfframp: true,
        });

        if (getIsLandscape()) {
          actions.setLandscapeActionsActiveTabIndex({ index: ActiveTab.Transfer });
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
          const hostWithProtocol = `https://${host}`;
          const matchingUrl = isSubproject(hostWithProtocol)
            ? hostWithProtocol
            : getGlobal().exploreData?.sites.find(({ url }) => {
              const siteHost = isTelegramUrl(url)
                ? new URL(url).pathname.split('/').filter(Boolean)[0]
                : new URL(url).hostname;

              return siteHost === host;
            })?.url;

          if (matchingUrl) {
            void openUrl(matchingUrl);
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

      case DeeplinkCommand.View: {
        const addressByChain: Partial<Record<ApiChain, string>> = {};
        const chains = getSupportedChains();

        chains.forEach((chain) => {
          const address = searchParams.get(chain);
          if (address && isValidAddressOrDomain(address, chain)) {
            addressByChain[chain] = address;
          }
        });

        if (!Object.keys(addressByChain).length) {
          actions.showError({ error: '$no_valid_view_addresses' });
          return false;
        }

        ensureNetwork(searchParams, currentNetwork);

        actions.openTemporaryViewAccount({ addressByChain });
        return true;
      }

      case DeeplinkCommand.Token: {
        const pathParts = pathname.split('/').filter(Boolean);

        if (pathParts.length < 2) {
          return false;
        }

        let tokenSlug: string | undefined;

        if (pathParts.length === 2) {
          // Format: mtw://token/{slug}
          tokenSlug = pathParts[1];
        } else if (pathParts.length === 3) {
          // Format: mtw://token/{chain}/{tokenAddress}
          const chain = pathParts[1];
          const tokenAddress = pathParts[2];

          tokenSlug = await callApi('buildTokenSlug', chain as ApiChain, tokenAddress);
        }

        if (!tokenSlug || !global.tokenInfo.bySlug[tokenSlug]) {
          actions.showError({ error: '$unknown_token_address' });
          return false;
        }

        actions.showTokenActivity({ slug: tokenSlug });
        return true;
      }

      case DeeplinkCommand.Transaction: {
        // Format: mtw://tx/{chain}/{txId}
        const pathParts = pathname.split('/');

        if (pathParts.length < 3) {
          return false;
        }

        const [, , chainPart, ...txIdParts] = pathParts;
        const txId = decodeURIComponent(txIdParts.join('/'));
        const chain = chainPart as ApiChain;

        if (!chain || !txId) {
          return false;
        }

        if (!getSupportedChains().includes(chain)) {
          actions.showError({ error: '$unsupported_chain' });
          return false;
        }

        const { network } = ensureNetwork(searchParams, currentNetwork);
        const shouldOpenViewAccount = IS_EXPLORER || network !== currentNetwork;

        const activities = await callApi('fetchTransactionById', {
          chain,
          network,
          txId,
          walletAddress: '',
        });

        if (!activities?.length) {
          actions.showError({ error: '$transaction_not_found' });
          return true;
        }

        // Get address from the first activity (toAddress for transactions, fromAddress for swaps)
        const activity = activities[0];
        const viewAddress = activity.kind === 'transaction'
          ? activity.toAddress
          : activity.kind === 'swap'
            ? activity.fromAddress
            : undefined;

        if (!viewAddress) {
          actions.showError({ error: '$could_not_determine_address' });
          return true;
        }

        if (shouldOpenViewAccount && !await openViewAccount(chain, viewAddress)) return false;

        // Pass activities to avoid duplicate API call
        actions.openTransactionInfo({ txId, chain, activities });
        return true;
      }

      case DeeplinkCommand.Nft: {
        // Format: mtw://nft/{nftAddress}
        const pathParts = pathname.split('/');
        const nftAddress = pathParts[2];

        if (!nftAddress) return false;

        const { network } = ensureNetwork(searchParams, currentNetwork);
        const shouldOpenViewAccount = IS_EXPLORER || network !== currentNetwork;

        const nft = await callApi('fetchNftByAddress', network, nftAddress);

        if (!nft) {
          actions.showError({ error: '$nft_not_found' });
          return false;
        }

        if (shouldOpenViewAccount) {
          const ownerAddress = nft.ownerAddress;

          if (!ownerAddress) {
            actions.showError({ error: '$could_not_determine_address' });
            return false;
          }

          if (!await openViewAccount('ton', ownerAddress)) {
            return false;
          }
        }

        actions.openNftAttributesModal({ nft, withOwner: true });
        return true;
      }
    }
  } catch (err) {
    logDebugError('processSelfDeeplink', err);
  }

  return false;
}

async function openViewAccount(
  chain: ApiChain,
  address: string,
): Promise<boolean> {
  const actions = getActions();
  let normalizedAddress: string | undefined;
  try {
    if (chain === 'ton') {
      const parsedAddress = Address.parse(address);
      if (parsedAddress) {
        normalizedAddress = parsedAddress.toRawString();
      }
    } else {
      normalizedAddress = address;
    }
  } catch (err: any) {
    actions.showError({ error: err.message || 'Unable to parse address' });
    logDebugError('openViewAccount', err);

    return false;
  }

  actions.openTemporaryViewAccount({ addressByChain: { [chain]: normalizedAddress } });

  const isReady = await waitFor(() => {
    const account = selectCurrentAccount(getGlobal());
    const currentAddress = account?.byChain[chain]?.address;
    if (!currentAddress) return false;

    return chain === 'ton'
      ? Address.parse(currentAddress).toRawString() === normalizedAddress
      : currentAddress === normalizedAddress;
  }, 100, 100);

  if (!isReady) {
    actions.showError({ error: 'Timed out waiting for account to be ready' });
  }

  return isReady;
}

function ensureNetwork(searchParams: URLSearchParams, currentNetwork: ApiNetwork) {
  const newNetwork: ApiNetwork = searchParams.get('testnet') === 'true' ? 'testnet' : 'mainnet';
  if (currentNetwork !== newNetwork) {
    getActions().changeNetwork({ network: newNetwork });
  }

  return {
    isTestnet: newNetwork === 'testnet',
    network: newNetwork,
  };
}

function getOfframpTokenMapping(
  baseCurrencyCode: string | undefined,
  global: GlobalState,
) {
  if (!baseCurrencyCode) {
    return undefined;
  }

  const normalizedCode = baseCurrencyCode.toLowerCase();

  if (normalizedCode === 'ton' || normalizedCode === 'toncoin') {
    return {
      chain: 'ton' as ApiChain,
      tokenSlug: TONCOIN.slug,
    };
  }

  const tokenBySlug = global.tokenInfo.bySlug[normalizedCode];
  if (tokenBySlug) {
    return {
      chain: tokenBySlug.chain,
      tokenSlug: tokenBySlug.slug,
    };
  }

  return undefined;
}

/**
 * Parses a deeplink and checks whether the transfer can be initiated.
 * See `parseTonDeeplink` for information about the returned values.
 */
export function parseDeeplinkTransferParams(url: string, global: GlobalState) {
  if (isTonDeeplink(url) || isSelfDeeplink(url)) {
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

  if (url.startsWith('tron:')) {
    return parseTronDeeplinkForTrx(url, global);
  }

  if (url.startsWith('tether:')) {
    return parseTronTetherDeeplink(url, global);
  }

  return undefined;
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
