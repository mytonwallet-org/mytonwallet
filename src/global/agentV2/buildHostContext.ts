import type { AgentApiChain } from '../../api/agentV2/protocol/types';
import type { AgentV2HostContextSnapshot } from '../../api/agentV2/types';
import type { GlobalState } from '../../global/types';

import {
  APP_VERSION,
  DEFAULT_CHAIN,
  IS_AIR_APP,
  IS_EXTENSION,
  IS_PACKAGED_ELECTRON,
  IS_TELEGRAM_APP,
  MYCOIN_MAINNET,
  MYCOIN_TESTNET,
} from '../../config';
import {
  selectAccountState,
  selectAccountTokens,
  selectIsStakingDisabled,
  selectPortfolioMainnetWalletKeys,
} from '../../global/selectors';
import { parseAccountId } from '../../util/account';
import { getIsSupportedChain, getOrderedAccountChains } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { calcVestingAmountByStatus } from '../../util/vesting';
import { buildAgentBuiltinDapps } from './builtinDapps';
import { AGENT_V2_CLASSIC_UI_CAPABILITIES } from './uiCapabilities';

import { getIsLandscape } from '../../hooks/useDeviceScreen';

const MAX_AGENT_HOST_ASSETS = 10_000;

interface AgentV2HostContextRelevantSlice {
  restrictions: GlobalState['restrictions'];
  accountsById: NonNullable<GlobalState['accounts']>['byId'] | undefined;
  areTokensWithNoCostHidden: GlobalState['settings']['areTokensWithNoCostHidden'];
  baseCurrency: GlobalState['settings']['baseCurrency'];
  byAccountId: GlobalState['byAccountId'];
  currencyRates: GlobalState['currencyRates'];
  currentAccountId: GlobalState['currentAccountId'];
  isTestnet: GlobalState['settings']['isTestnet'];
  langCode: GlobalState['settings']['langCode'];
  settingsByAccountId: GlobalState['settings']['byAccountId'];
  theme: GlobalState['settings']['theme'];
  tokenInfoBySlug: GlobalState['tokenInfo']['bySlug'];
  swapTokenInfo: GlobalState['swapTokenInfo'];
}

type BuildAgentV2HostContext = (global: GlobalState) => AgentV2HostContextSnapshot;

export function createAgentV2HostContextSelector(
  buildHostContext: BuildAgentV2HostContext = buildAgentV2HostContext,
) {
  let previousSlice: AgentV2HostContextRelevantSlice | undefined;
  let previousHostContext: AgentV2HostContextSnapshot | undefined;

  return (global: GlobalState) => {
    const slice = selectAgentV2HostContextRelevantSlice(global);
    if (previousSlice && areAgentV2HostContextSlicesEqual(previousSlice, slice)) {
      return previousHostContext!;
    }

    previousSlice = slice;
    previousHostContext = buildHostContext(global);
    return previousHostContext;
  };
}

export const selectAgentV2HostContext = createAgentV2HostContextSelector();

export function buildAgentV2HostContext(global: GlobalState): AgentV2HostContextSnapshot {
  const activePortfolioWalletKeys = selectPortfolioMainnetWalletKeys(global);
  const accounts = Object.entries(global.accounts?.byId ?? {}).map(([accountId, account]) => {
    // Every network of the account in the order the app shows them; a network the app no longer has is left out
    const chains = getOrderedAccountChains(account.byChain);
    const addresses = Object.fromEntries(chains.flatMap((chain) => {
      const address = account.byChain[chain]?.address;
      return address ? [[chain, address]] : [];
    }));
    const tokens = (selectAccountTokens(global, accountId) ?? [])
      .filter((token) => chains.includes(token.chain) && isAgentAssetMetadataValid(token));
    const accountState = selectAccountState(global, accountId);
    const tokenBySlug = new Map(tokens.map((token) => [token.slug, token]));
    const savedAddresses = (accountState?.savedAddresses ?? [])
      .filter(({ chain }) => getIsSupportedChain(chain))
      .map(({ name, chain, address }) => ({
        id: `${chain}:${address}`,
        name,
        chain: chain as AgentApiChain,
        address,
      }));
    const { network } = parseAccountId(accountId);
    const mycoin = network === 'testnet' ? MYCOIN_TESTNET : MYCOIN_MAINNET;
    // The token record is the identity holdings use; the constants cover a missing record
    const mycoinToken = global.tokenInfo.bySlug[mycoin.slug];
    const mycoinAsset = buildAgentHostAsset(mycoinToken && isAgentAssetMetadataValid(mycoinToken)
      ? mycoinToken
      : { ...mycoin, tokenAddress: mycoin.minterAddress });
    const portfolioWalletKeys = accountId === global.currentAccountId
      ? activePortfolioWalletKeys
      : network === 'mainnet'
        ? Object.entries(addresses).map(([chain, address]) => `${chain}:${address}`)
        : [];
    const extraPositions = [
      // An NFT on a network the app no longer has is left out, as tokens are
      ...Object.values(accountState?.nfts?.byAddress ?? {}).filter((nft) => chains.includes(nft.chain)).map((nft) => ({
        id: `nft-${nft.address}`,
        kind: 'nft' as const,
        chain: nft.chain as AgentApiChain,
        label: nft.name || nft.collectionName || 'NFT',
        valuationStatus: 'not_applicable' as const,
        visibility: nft.isHidden ? 'hidden' as const : 'visible' as const,
        ...(nft.collectionName ? { collection: nft.collectionName } : {}),
        isOnSale: nft.isOnSale,
        ...(nft.isScam ? { riskVerdict: 'spam' as const } : {}),
      })),
      ...Object.values(accountState?.staking?.stateById ?? {}).flatMap((staking) => {
        const token = tokenBySlug.get(staking.tokenSlug);
        if (!token || staking.balance <= 0n) return [];
        return [{
          id: `staking-${staking.id}`,
          kind: 'staking' as const,
          chain: token.chain as AgentApiChain,
          label: `${token.symbol} staking`,
          asset: buildAgentHostAsset(token),
          quantity: toDecimal(staking.balance, token.decimals, true),
          valuationStatus: 'unpriced' as const,
          visibility: 'visible' as const,
          status: staking.unstakeRequestAmount ? 'unstaking' : 'active',
          apy: String(staking.annualYield),
          ...('unclaimedRewards' in staking && staking.unclaimedRewards > 0n
            ? { rewards: toDecimal(staking.unclaimedRewards, token.decimals, true) }
            : {}),
        }];
      }),
      ...(accountState?.vesting?.info ?? []).flatMap((vesting) => {
        const remaining = calcVestingAmountByStatus([vesting], ['frozen', 'ready']);
        const hasMalformedPart = vesting.parts.some(({ amount }) => !Number.isFinite(amount));
        return hasMalformedPart || isPositiveDecimal(remaining) ? [{
          id: `vesting-${vesting.id}`,
          kind: 'vesting' as const,
          chain: mycoinAsset.chain,
          label: vesting.title,
          asset: mycoinAsset,
          // Without a quantity, wallet queries report a malformed vesting as an invalid row
          ...(hasMalformedPart ? {} : { quantity: remaining }),
          valuationStatus: 'unpriced' as const,
          visibility: 'visible' as const,
          status: vesting.parts.some(({ status }) => status === 'ready') ? 'ready' : 'frozen',
        }] : [];
      }),
    ];
    return {
      accountId,
      ...(account.title ? { label: account.title } : {}),
      state: 'active' as const,
      accountType: account.type === 'view'
        ? 'viewOnly' as const
        : account.type === 'hardware'
          ? 'ledger' as const
          : 'regular' as const,
      isViewOnly: account.type === 'view',
      chains,
      addresses,
      portfolioWalletKeys,
      holdings: tokens.map((token) => ({
        asset: buildAgentHostAsset(token),
        balance: toDecimal(token.amount, token.decimals, true),
        availableBalance: toDecimal(token.amount, token.decimals, true),
        valuationStatus: isPositiveDecimal(token.totalValue)
          ? 'valued' as const
          : 'unpriced' as const,
        visibility: token.isDisabled ? 'hidden' as const : 'visible' as const,
        ...(token.totalValue ? { fiatValue: token.totalValue } : {}),
        ...(canonicalPositiveNumber(token.price) ? { fiatPrice: canonicalPositiveNumber(token.price) } : {}),
      })),
      positions: extraPositions,
      savedAddresses,
      nftLoadedChains: chains.filter((chain) => accountState?.nfts?.isFullLoadCompleteByChain?.[chain]),
      domainStates: {
        accounts: { state: 'fresh' as const },
        fungible: { state: accountState?.balances ? 'fresh' as const : 'notLoaded' as const },
        staking: {
          state: !chains.includes('ton') || accountState?.staking?.stateById !== undefined
            ? 'fresh' as const : 'notLoaded' as const,
        },
        vesting: {
          state: !chains.includes('ton') || accountState?.vesting?.info !== undefined
            ? 'fresh' as const : 'notLoaded' as const,
        },
        vault: { state: 'unavailable' as const },
        transactions: {
          state: accountState?.activities?.idsMain === undefined ? 'notLoaded' as const : 'fresh' as const,
        },
        // Saved addresses are local account metadata. Once the account state is
        // present, an absent property is the authoritative empty address book.
        contacts: { state: accountState === undefined ? 'notLoaded' as const : 'fresh' as const },
        value_series: {
          state: portfolioWalletKeys.length ? 'stale' as const : 'unavailable' as const,
        },
      },
    };
  });
  const activeAccount = accounts.find(({ accountId }) => accountId === global.currentAccountId);
  // The wallet's own network when the account has it, else its first network in the app's order, as on iOS and Android
  const activeNetwork = activeAccount?.chains.includes(DEFAULT_CHAIN) ? DEFAULT_CHAIN : activeAccount?.chains[0];
  const assetCatalog = Object.values(global.tokenInfo.bySlug)
    .filter((token) => getIsSupportedChain(token.chain) && isAgentAssetMetadataValid(token))
    .sort(compareSlugs)
    .slice(0, MAX_AGENT_HOST_ASSETS)
    .map((token) => ({
      ...buildAgentHostAsset(token),
      ...(canonicalPositiveNumber(token.priceUsd) ? { priceUsd: canonicalPositiveNumber(token.priceUsd) } : {}),
      ...(canonicalFiniteNumber(token.percentChange24h) !== undefined
        ? { percentChange24h: canonicalFiniteNumber(token.percentChange24h) }
        : {}),
    }));
  const swapTokenInfo = global.swapTokenInfo;
  const swapAssetCatalog = swapTokenInfo?.isLoaded
    ? Object.values(swapTokenInfo.bySlug)
      .filter((token) => getIsSupportedChain(token.chain) && isAgentAssetMetadataValid(token))
      .sort(compareSlugs)
      .slice(0, MAX_AGENT_HOST_ASSETS)
      .map((token) => ({
        ...buildAgentHostAsset(token),
        ...(canonicalPositiveNumber(token.priceUsd) ? { priceUsd: canonicalPositiveNumber(token.priceUsd) } : {}),
      }))
    : undefined;
  const currencyRate = canonicalPositiveNumber(Number(global.currencyRates[global.settings.baseCurrency]));

  return {
    platform: 'classic',
    uiCapabilities: AGENT_V2_CLASSIC_UI_CAPABILITIES,
    builtinDapps: buildAgentBuiltinDapps(global),
    client: getClientKind(),
    isLandscape: getIsLandscape(),
    lang: global.settings.langCode,
    baseCurrency: global.settings.baseCurrency,
    ...(currencyRate ? { currencyRate } : {}),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    appVersion: APP_VERSION,
    theme: global.settings.theme,
    isTestnet: global.settings.isTestnet,
    ...(activeAccount ? { activeAccountId: activeAccount.accountId } : {}),
    ...(activeNetwork ? { activeNetwork } : {}),
    isStakingDisabled: selectIsStakingDisabled(global),
    accounts,
    assetCatalog,
    ...(swapAssetCatalog ? { swapAssetCatalog } : {}),
    savedAddresses: activeAccount?.savedAddresses ?? [],
  };
}

function buildAgentHostAsset({
  slug,
  chain,
  symbol,
  name,
  tokenAddress,
  decimals,
}: Readonly<{ slug: string; chain: string; symbol: string; name: string; tokenAddress?: string; decimals: number }>) {
  return {
    slug,
    chain,
    symbol,
    name,
    ...(tokenAddress ? { tokenAddress } : {}),
    decimals,
  };
}

/** A catalog over its limit keeps its first assets by slug, the same on every platform and launch */
function compareSlugs(left: Readonly<{ slug: string }>, right: Readonly<{ slug: string }>) {
  return left.slug < right.slug ? -1 : left.slug > right.slug ? 1 : 0;
}

function isAgentAssetMetadataValid({
  slug,
  symbol,
  decimals,
}: Readonly<{ slug: string; symbol: string; decimals: number }>) {
  return Boolean(slug && symbol && Number.isInteger(decimals) && decimals >= 0);
}

function selectAgentV2HostContextRelevantSlice(global: GlobalState): AgentV2HostContextRelevantSlice {
  return {
    accountsById: global.accounts?.byId,
    restrictions: global.restrictions,
    areTokensWithNoCostHidden: global.settings.areTokensWithNoCostHidden,
    baseCurrency: global.settings.baseCurrency,
    byAccountId: global.byAccountId,
    currencyRates: global.currencyRates,
    currentAccountId: global.currentAccountId,
    isTestnet: global.settings.isTestnet,
    langCode: global.settings.langCode,
    settingsByAccountId: global.settings.byAccountId,
    theme: global.settings.theme,
    tokenInfoBySlug: global.tokenInfo.bySlug,
    swapTokenInfo: global.swapTokenInfo,
  };
}

function areAgentV2HostContextSlicesEqual(
  first: AgentV2HostContextRelevantSlice,
  second: AgentV2HostContextRelevantSlice,
) {
  return first.restrictions === second.restrictions
    && first.accountsById === second.accountsById
    && first.areTokensWithNoCostHidden === second.areTokensWithNoCostHidden
    && first.baseCurrency === second.baseCurrency
    && first.byAccountId === second.byAccountId
    && first.currencyRates === second.currencyRates
    && first.currentAccountId === second.currentAccountId
    && first.langCode === second.langCode
    && first.isTestnet === second.isTestnet
    && first.settingsByAccountId === second.settingsByAccountId
    && first.theme === second.theme
    && first.tokenInfoBySlug === second.tokenInfoBySlug
    && first.swapTokenInfo === second.swapTokenInfo;
}

function isPositiveDecimal(value?: string) {
  return Boolean(value && /^(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(value) && /[1-9]/u.test(value));
}

function canonicalPositiveNumber(value: number) {
  if (!Number.isFinite(value) || value <= 0) return undefined;
  return value.toFixed(18).replace(/(?:\.0+|(?<fraction>\.\d*?)0+)$/u, '$<fraction>');
}

function canonicalFiniteNumber(value?: number) {
  if (value === undefined || !Number.isFinite(value)) return undefined;
  return value.toFixed(18).replace(/(?:\.0+|(?<fraction>\.\d*?)0+)$/u, '$<fraction>');
}

function getClientKind(): AgentV2HostContextSnapshot['client'] {
  if (IS_AIR_APP) return 'capacitor';
  if (IS_PACKAGED_ELECTRON) return 'electron';
  if (IS_EXTENSION) return 'extension';
  if (IS_TELEGRAM_APP) return 'tma';
  return 'web';
}
