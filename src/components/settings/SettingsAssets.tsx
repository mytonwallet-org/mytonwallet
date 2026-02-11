import { AirAppLauncher } from '@mytonwallet/air-app-launcher';
import React, {
  memo, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft, ApiStakingState } from '../../api/types';
import { SettingsState, type UserToken } from '../../global/types';

import { CURRENCIES, IS_CAPACITOR, TINY_TRANSFER_MAX_COST } from '../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsMultichainAccount,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useTokensWithStaking from '../../hooks/useTokensWithStaking';

import Button from '../ui/Button';
import Dropdown, { type DropdownItem } from '../ui/Dropdown';
import IconWithTooltip from '../ui/IconWithTooltip';
import ModalHeader from '../ui/ModalHeader';
import Switcher from '../ui/Switcher';
import SettingsTokens from './SettingsTokens';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  isInsideModal?: boolean;
  onBack: NoneToVoidFunction;
}

interface StateProps {
  isInvestorViewEnabled?: boolean;
  areTinyTransfersHidden?: boolean;
  areTokensWithNoCostHidden?: boolean;
  isSensitiveDataHidden?: true;
  baseCurrency: ApiBaseCurrency;
  isMultichainAccount: boolean;
  tokens?: UserToken[];
  pinnedSlugs?: string[];
  alwaysHiddenSlugs?: string[];
  nftsByAddress?: Record<string, ApiNft>;
  blacklistedNftAddresses: string[];
  whitelistedNftAddresses: string[];
  states?: ApiStakingState[];
  currencyRates?: ApiCurrencyRates;
}

function SettingsAssets({
  isActive,
  isInsideModal,
  isInvestorViewEnabled,
  isSensitiveDataHidden,
  areTinyTransfersHidden,
  areTokensWithNoCostHidden,
  baseCurrency,
  isMultichainAccount,
  tokens,
  pinnedSlugs,
  alwaysHiddenSlugs = MEMO_EMPTY_ARRAY,
  nftsByAddress,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  states,
  currencyRates,
  onBack,
}: OwnProps & StateProps) {
  const {
    toggleTinyTransfersHidden,
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

  useHistoryBack({ isActive, onBack });

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

  const handleInvestorViewToggle = useLastCallback(() => {
    toggleInvestorView({ isEnabled: !isInvestorViewEnabled });
  });

  const handleOpenHiddenNfts = useLastCallback(() => {
    setSettingsState({ state: SettingsState.HiddenNfts });
  });

  const handleTokensWithNoPriceToggle = useLastCallback(() => {
    toggleTokensWithNoCost({ isEnabled: !areTokensWithNoCostHidden });
  });

  const [localBaseCurrency, setLocalBaseCurrency] = useState(baseCurrency);

  const handleBaseCurrencyChange = useLastCallback((currency: ApiBaseCurrency) => {
    setLocalBaseCurrency(currency);
    changeBaseCurrency({ currency });
    if (IS_CAPACITOR) void AirAppLauncher.setBaseCurrency({ currency });
  });

  const {
    shouldRenderHiddenNftsSection,
    hiddenNftsCount,
  } = useMemo(() => {
    const nfts = Object.values(nftsByAddress || {});
    const blacklistedAddressesSet = new Set(blacklistedNftAddresses);
    const whitelistedAddressesSet = new Set(whitelistedNftAddresses);
    const shouldRender = nfts.some((nft) => blacklistedAddressesSet.has(nft.address) || nft.isHidden);
    const hiddenNfts = nfts.filter(
      (nft) => !whitelistedAddressesSet.has(nft.address) && (blacklistedAddressesSet.has(nft.address) || nft.isHidden),
    );

    return {
      shouldRenderHiddenNftsSection: shouldRender,
      hiddenNftsCount: hiddenNfts.length,
    };
  }, [nftsByAddress, blacklistedNftAddresses, whitelistedNftAddresses]);

  return (
    <div className={styles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('Assets & Activity')}
          withNotch={isScrolled}
          onBackButtonClick={onBack}
          className={styles.modalHeader}
        />
      ) : (
        <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={onBack} className={styles.headerBack}>
            <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={styles.headerTitle}>{lang('Assets & Activity')}</span>
        </div>
      )}
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
              {lang('Investor View')}
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
              {lang('Hide Tiny Transfers')}
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
        </div>
        {
          shouldRenderHiddenNftsSection && (
            <div className={styles.settingsBlock}>
              <div className={buildClassName(styles.item, styles.item_small)} onClick={handleOpenHiddenNfts}>
                {lang('Hidden NFTs')}
                <div className={styles.itemInfo}>
                  {hiddenNftsCount}
                  <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
                </div>
              </div>
            </div>
          )
        }
        <p className={styles.blockTitle}>{lang('Token Settings')}</p>
        <div className={styles.settingsBlock}>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleTokensWithNoPriceToggle}>
            <div>
              {lang('Hide Tokens With No Cost')}
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
        </div>

        <SettingsTokens
          isSensitiveDataHidden={isSensitiveDataHidden}
          tokens={tokensWithStaking}
          pinnedSlugs={pinnedSlugs}
          baseCurrency={baseCurrency}
          withChainIcon={isMultichainAccount}
        />
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isInvestorViewEnabled,
    areTinyTransfersHidden,
    areTokensWithNoCostHidden,
    baseCurrency,
    isSensitiveDataHidden,
  } = global.settings;

  const { pinnedSlugs, alwaysHiddenSlugs } = selectCurrentAccountSettings(global) ?? {};

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
    areTokensWithNoCostHidden,
    baseCurrency,
    isMultichainAccount: selectIsMultichainAccount(global, currentAccountId!),
    tokens: selectCurrentAccountTokens(global),
    pinnedSlugs,
    alwaysHiddenSlugs,
    nftsByAddress,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    isSensitiveDataHidden,
    states: selectAccountStakingStates(global, currentAccountId!),
    currencyRates: global.currencyRates,
  };
})(SettingsAssets));
