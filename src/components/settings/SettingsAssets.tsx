import React, {
  memo, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiChain, ApiCurrencyRates, ApiNft, ApiStakingState } from '../../api/types';
import { SettingsState, type UserToken } from '../../global/types';

import { CURRENCIES, TINY_TRANSFER_MAX_COST } from '../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountChainDisplay,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectHasLocalizedTokenNames,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useTokensWithStaking from '../../hooks/useTokensWithStaking';

import Dropdown, { type DropdownItem } from '../ui/Dropdown';
import IconWithTooltip from '../ui/IconWithTooltip';
import Switcher from '../ui/Switcher';
import SettingsHeader from './SettingsHeader';
import SettingsTokens from './SettingsTokens';

import styles from './Settings.module.scss';

const MAX_STACKED_CHAINS = 10;

interface OwnProps {
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  isInvestorViewEnabled?: boolean;
  areTinyTransfersHidden?: boolean;
  areUnverifiedNftsHidden?: boolean;
  areTokensWithNoCostHidden?: boolean;
  areTokenNamesLocalized?: boolean;
  hasLocalizedTokenNames?: boolean;
  isSensitiveDataHidden?: true;
  baseCurrency: ApiBaseCurrency;
  tokens?: UserToken[];
  pinnedSlugs?: string[];
  alwaysHiddenSlugs?: string[];
  accountChainCount: number;
  visibleChains: ApiChain[];
  nftsByAddress?: Record<string, ApiNft>;
  blacklistedNftAddresses: string[];
  whitelistedNftAddresses: string[];
  states?: ApiStakingState[];
  currencyRates?: ApiCurrencyRates;
}

function SettingsAssets({
  isActive,
  isInvestorViewEnabled,
  isSensitiveDataHidden,
  areTinyTransfersHidden,
  areUnverifiedNftsHidden,
  areTokensWithNoCostHidden,
  areTokenNamesLocalized,
  hasLocalizedTokenNames,
  baseCurrency,
  tokens,
  pinnedSlugs,
  alwaysHiddenSlugs = MEMO_EMPTY_ARRAY,
  accountChainCount,
  visibleChains,
  nftsByAddress,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  states,
  currencyRates,
  onBackClick,
}: OwnProps & StateProps) {
  const {
    toggleTinyTransfersHidden,
    toggleUnverifiedNftsHidden,
    toggleLocalizedTokenNames,
    toggleInvestorView,
    toggleTokensWithNoCost,
    changeBaseCurrency,
    setSettingsState,
  } = getActions();

  const lang = useLang();

  const scrollContainerRef = useRef<HTMLDivElement>();

  const tokensWithStaking = useTokensWithStaking({
    tokens,
    states,
    baseCurrency,
    currencyRates,
    pinnedSlugs,
    alwaysHiddenSlugs,
  });

  useHistoryBack({ isActive, onBack: onBackClick });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const currencyItems = useMemo<DropdownItem<ApiBaseCurrency>[]>(() => (
    Object.entries(CURRENCIES)
      .map(([currency, { name }]) => ({ value: currency as keyof typeof CURRENCIES, name }))
  ), []);

  const handleTinyTransfersHiddenToggle = useLastCallback(() => {
    toggleTinyTransfersHidden({ isEnabled: !areTinyTransfersHidden });
  });

  const handleUnverifiedNftsHiddenToggle = useLastCallback(() => {
    toggleUnverifiedNftsHidden({ isEnabled: !areUnverifiedNftsHidden });
  });

  const handleLocalizedTokenNamesToggle = useLastCallback(() => {
    toggleLocalizedTokenNames({ isEnabled: !areTokenNamesLocalized });
  });

  const handleInvestorViewToggle = useLastCallback(() => {
    toggleInvestorView({ isEnabled: !isInvestorViewEnabled });
  });

  const handleOpenHiddenNfts = useLastCallback(() => {
    setSettingsState({ state: SettingsState.HiddenNfts });
  });

  const handleOpenChains = useLastCallback(() => {
    setSettingsState({ state: SettingsState.Chains });
  });

  // Collapse into the badge only when it hides at least two chains
  const { stackedChains, collapsedChainCount } = useMemo(() => {
    const stacked = visibleChains.length > MAX_STACKED_CHAINS + 1
      ? visibleChains.slice(0, MAX_STACKED_CHAINS)
      : visibleChains;

    return { stackedChains: stacked, collapsedChainCount: visibleChains.length - stacked.length };
  }, [visibleChains]);

  const handleTokensWithNoPriceToggle = useLastCallback(() => {
    toggleTokensWithNoCost({ isEnabled: !areTokensWithNoCostHidden });
  });

  const [localBaseCurrency, setLocalBaseCurrency] = useState(baseCurrency);

  const handleBaseCurrencyChange = useLastCallback((currency: ApiBaseCurrency) => {
    setLocalBaseCurrency(currency);
    changeBaseCurrency({ currency });
  });

  const {
    shouldRenderHiddenNftsSection,
    hiddenNftsCount,
  } = useMemo(() => {
    const nfts = Object.values(nftsByAddress || {});
    const blacklistedAddressesSet = new Set(blacklistedNftAddresses);
    const whitelistedAddressesSet = new Set(whitelistedNftAddresses);
    const getIsHideable = (nft: ApiNft) => blacklistedAddressesSet.has(nft.address)
      || nft.isHidden
      || (areUnverifiedNftsHidden && nft.isUnverified);
    const shouldRender = nfts.some(getIsHideable);
    const hiddenNfts = nfts.filter(
      (nft) => !whitelistedAddressesSet.has(nft.address) && getIsHideable(nft),
    );

    return {
      shouldRenderHiddenNftsSection: shouldRender,
      hiddenNftsCount: hiddenNfts.length,
    };
  }, [nftsByAddress, blacklistedNftAddresses, whitelistedNftAddresses, areUnverifiedNftsHidden]);

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Assets & Activity')} isScrolled={isScrolled} onBackClick={onBackClick} />

      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
        ref={scrollContainerRef}
      >
        <div className={styles.settingsBlock}>
          <Dropdown
            label={lang('Base Currency')}
            items={currencyItems}
            selectedValue={baseCurrency}
            theme="light"
            shouldTranslateOptions
            className={buildClassName(styles.item, styles.item_small)}
            onChange={handleBaseCurrencyChange}
            isLoading={localBaseCurrency !== baseCurrency}
          />
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleInvestorViewToggle}>
            <div>
              <span className={styles.itemTitle}>{lang('Investor View')}</span>
              {' '}
              <IconWithTooltip
                message={lang('Focus on asset value rather than current balance')}
                iconClassName={styles.iconQuestion}
              />
            </div>

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Investor View')}
              checked={isInvestorViewEnabled}
            />
          </div>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleTinyTransfersHiddenToggle}>
            <div>
              <span className={styles.itemTitle}>{lang('Hide Tiny Transfers')}</span>
              {' '}
              <IconWithTooltip
                message={
                  lang(
                    '$tiny_transfers_help',
                    { value: TINY_TRANSFER_MAX_COST },
                  ) as string
                }
                tooltipClassName={buildClassName(styles.wideTooltip)}
                iconClassName={styles.iconQuestion}
              />
            </div>

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Hide Tiny Transfers')}
              checked={areTinyTransfersHidden}
            />
          </div>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleUnverifiedNftsHiddenToggle}>
            <span className={styles.itemTitle}>{lang('Hide Unverified NFTs')}</span>

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Hide Unverified NFTs')}
              checked={areUnverifiedNftsHidden}
            />
          </div>
        </div>
        {
          shouldRenderHiddenNftsSection && (
            <div className={styles.settingsBlock}>
              <div className={buildClassName(styles.item, styles.item_small)} onClick={handleOpenHiddenNfts}>
                <span className={styles.itemTitle}>{lang('Hidden NFTs')}</span>
                <div className={styles.itemInfo}>
                  {hiddenNftsCount}
                  <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                </div>
              </div>
            </div>
          )
        }
        {accountChainCount > 1 && (
          <>
            <p className={styles.blockTitle}>{lang('Blockchains')}</p>
            <div className={styles.settingsBlock}>
              <div className={buildClassName(styles.item, styles.item_small)} onClick={handleOpenChains}>
                <div className={styles.chainIconList}>
                  {stackedChains.map((chain) => (
                    <img
                      key={chain}
                      src={getChainNetworkIcon(chain)}
                      alt={getChainTitle(chain)}
                      className={styles.stackedChainIcon}
                    />
                  ))}
                  {collapsedChainCount > 0 && (
                    <span className={styles.stackedChainMore}>
                      +{collapsedChainCount}
                    </span>
                  )}
                </div>
                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
              </div>
            </div>
          </>
        )}
        <p className={styles.blockTitle}>{lang('Token Settings')}</p>
        <div className={styles.settingsBlock}>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleTokensWithNoPriceToggle}>
            <div>
              <span className={styles.itemTitle}>{lang('Hide Tokens With No Cost')}</span>
              {' '}
              <IconWithTooltip
                message={
                  lang(
                    '$hide_tokens_no_cost_help',
                    { value: TINY_TRANSFER_MAX_COST },
                  ) as string
                }
                tooltipClassName={buildClassName(styles.wideTooltip)}
                iconClassName={styles.iconQuestion}
              />
            </div>

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Hide Tokens With No Cost')}
              checked={areTokensWithNoCostHidden}
            />
          </div>
          {hasLocalizedTokenNames && (
            <div className={buildClassName(styles.item, styles.item_small)} onClick={handleLocalizedTokenNamesToggle}>
              <span className={styles.itemTitle}>{lang('Localized Token Names')}</span>

              <Switcher
                className={styles.menuSwitcher}
                label={lang('Localized Token Names')}
                checked={areTokenNamesLocalized}
              />
            </div>
          )}
        </div>

        <SettingsTokens
          isActive={isActive}
          isSensitiveDataHidden={isSensitiveDataHidden}
          areTokenNamesLocalized={areTokenNamesLocalized}
          tokens={tokensWithStaking}
          pinnedSlugs={pinnedSlugs}
          baseCurrency={baseCurrency}
        />
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isInvestorViewEnabled,
    areTinyTransfersHidden,
    areUnverifiedNftsHidden,
    areTokensWithNoCostHidden,
    areTokenNamesLocalized,
    baseCurrency,
    isSensitiveDataHidden,
  } = global.settings;

  const { pinnedSlugs, alwaysHiddenSlugs } = selectCurrentAccountSettings(global) ?? {};
  const { defaultOrder, visibleChains } = selectCurrentAccountChainDisplay(global) ?? {};

  const currentAccountId = selectCurrentAccountId(global);
  const {
    blacklistedNftAddresses = MEMO_EMPTY_ARRAY,
    whitelistedNftAddresses = MEMO_EMPTY_ARRAY,
    nfts: {
      byAddress: nftsByAddress,
    } = {},
  } = selectCurrentAccountState(global) || {};

  return {
    isInvestorViewEnabled,
    areTinyTransfersHidden,
    areUnverifiedNftsHidden,
    areTokensWithNoCostHidden,
    areTokenNamesLocalized,
    hasLocalizedTokenNames: selectHasLocalizedTokenNames(global),
    baseCurrency,
    tokens: selectCurrentAccountTokens(global),
    pinnedSlugs,
    alwaysHiddenSlugs,
    accountChainCount: defaultOrder?.length ?? 0,
    visibleChains: visibleChains ?? MEMO_EMPTY_ARRAY,
    nftsByAddress,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    isSensitiveDataHidden,
    states: selectAccountStakingStates(global, currentAccountId!),
    currencyRates: global.currencyRates,
  };
})(SettingsAssets));
