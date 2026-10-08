import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiChain, ApiCurrencyRates, ApiSwapVersion } from '../../api/types';
import type { TradeDirection } from '../../global/types';
import type { TokenType } from '../../util/tokenSearch';
import type { TabWithProperties } from '../ui/TabList';
import type { TradeCategory } from './helpers/buildTradeSections';
import { type AssetPairs, SettingsState, type UserSwapToken } from '../../global/types';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX, CURRENCIES } from '../../config';
import {
  selectAvailableUserForSwapTokens,
  selectCurrentAccount,
  selectCurrentAccountSettings,
  selectPopularTokens,
  selectSwapTokens,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { calculateTokenPrice } from '../../util/calculatePrice';
import { getChainConfig, getStablecoinSlugs } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import { getChainFromAddress } from '../../util/isValidAddress';
import { disableSwipeToClose, enableSwipeToClose } from '../../util/modalSwipeManager';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import { isSwapPairValid } from '../../util/swap/isSwapPairValid';
import { getIsRwaStockToken, getTokenName } from '../../util/tokens';
import { findTokensByQuery } from '../../util/tokenSearch';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';
import { buildTradeSections, MIN_OWNED_TOKENS_FOR_CATEGORIES, TRADE_CATEGORIES } from './helpers/buildTradeSections';

import useDebouncedValue from '../../hooks/useDebouncedValue';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useSyncEffect from '../../hooks/useSyncEffect';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import ModalHeader from '../ui/ModalHeader';
import SensitiveData from '../ui/SensitiveData';
import TabList from '../ui/TabList';
import Transition from '../ui/Transition';
import FiatCurrencyIcon from './FiatCurrencyIcon';
import TokenIcon from './TokenIcon';
import TokenTitle from './TokenTitle';

import styles from './TokenSelector.module.scss';

interface OwnProps {
  isActive?: boolean;
  shouldFilter?: boolean;
  shouldUseSwapTokens?: boolean;
  shouldHideMyTokens?: boolean;
  shouldHideNotSupportedTokens?: boolean;
  isSwapOut?: boolean;
  selectedChain?: ApiChain | ApiChain[];
  searchTokens?: TokenType[];
  noHeader?: boolean;
  searchClassName?: string;
  /** Turns the picker into the Buy / Sell asset browser: category tabs, fiat currencies and the trade grouping */
  tradeDirection?: TradeDirection;
  fiatCurrencies?: ApiBaseCurrency[];
  onClose: NoneToVoidFunction;
  onBack: NoneToVoidFunction;
  onTokenSelect: (token: TokenType) => void;
  onFiatSelect?: (currency: ApiBaseCurrency) => void;
}

interface StateProps {
  token?: TokenType;
  userTokens?: TokenType[];
  popularTokens?: TokenType[];
  swapTokens?: UserSwapToken[];
  tokenInSlug?: string;
  tokenOutSlug?: string;
  pairsBySlug?: Record<string, AssetPairs>;
  swapVersion: ApiSwapVersion;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  isLoading?: boolean;
  error?: string;
  availableChains?: Partial<Record<ApiChain, unknown>>;
  importedSlugs?: string[];
  isSensitiveDataHidden?: true;
}

enum SearchState {
  Initial,
  Search,
  Loading,
  TokenByAddress,
  Empty,
}

const EMPTY_ARRAY: never[] = [];
const EMPTY_OBJECT = {};
const SEARCH_DEBOUNCE_MS = 200;

function TokenSelector({
  token: tokenProp,
  userTokens: userTokensProp = EMPTY_ARRAY,
  swapTokens = EMPTY_ARRAY,
  popularTokens: popularTokensProp = EMPTY_ARRAY,
  noHeader,
  searchClassName,
  shouldFilter,
  shouldUseSwapTokens,
  baseCurrency,
  currencyRates,
  tokenInSlug,
  tokenOutSlug,
  pairsBySlug,
  swapVersion,
  isActive,
  isLoading,
  error,
  shouldHideMyTokens,
  shouldHideNotSupportedTokens = false,
  availableChains = EMPTY_OBJECT,
  selectedChain,
  searchTokens,
  tradeDirection,
  fiatCurrencies = EMPTY_ARRAY,
  importedSlugs,
  isSensitiveDataHidden,
  onTokenSelect,
  onFiatSelect,
  onBack,
  onClose,
}: OwnProps & StateProps) {
  const { importToken, resetImportToken, openSettingsWithState } = getActions();
  const lang = useLang();

  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const scrollContainerRef = useRef<HTMLDivElement>();
  const searchInputRef = useRef<HTMLInputElement>();
  const isTradeMode = Boolean(tradeDirection);

  useHistoryBack({
    isActive,
    onBack,
  });

  useEffect(() => {
    if (!isActive) return undefined;

    disableSwipeToClose();

    return enableSwipeToClose;
  }, [isActive]);

  useFocusAfterAnimation(searchInputRef, !isActive);

  const {
    handleScroll: handleContentScroll,
  } = useScrolledState();

  const [searchValue, setSearchValue] = useState('');
  const debouncedSearchValue = useDebouncedValue(searchValue, SEARCH_DEBOUNCE_MS);
  const [isResetButtonVisible, setIsResetButtonVisible] = useState(false);
  const [renderingKey, setRenderingKey] = useState(SearchState.Initial);
  const [searchTokenList, setSearchTokenList] = useState<TokenType[]>([]);
  const [category, setCategory] = useState<TradeCategory>('all');

  const selectedChains = useMemo(
    () => selectedChain && new Set(Array.isArray(selectedChain) ? selectedChain : [selectedChain]),
    [selectedChain],
  );

  // It is necessary to use useCallback instead of useLastCallback here
  const filterTokens = useCallback((tokens: TokenType[]) => {
    return shouldFilter
      ? filterAndSortTokens(tokens, availableChains, tokenInSlug, pairsBySlug, swapVersion)
      : tokens;
  }, [shouldFilter, availableChains, tokenInSlug, pairsBySlug, swapVersion]);

  const token = useMemo(
    () => tokenProp ? filterTokens([tokenProp])[0] : undefined,
    [tokenProp, filterTokens],
  );

  const userTokens = useMemo(
    () => filterSupportedTokens(userTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains),
    [userTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains],
  );

  const allTokens = useMemo(
    () => filterSupportedTokens(
      searchTokens ?? swapTokens,
      shouldHideNotSupportedTokens,
      availableChains,
      selectedChains,
    ),
    [searchTokens, swapTokens, shouldHideNotSupportedTokens, availableChains, selectedChains],
  );

  const popularTokens = useMemo(
    () => filterSupportedTokens(popularTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains),
    [popularTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains],
  );

  const userTokensWithFilter = useMemo(() => filterTokens(userTokens), [filterTokens, userTokens]);
  const popularTokensWithFilter = useMemo(() => filterTokens(popularTokens), [filterTokens, popularTokens]);
  const swapTokensWithFilter = useMemo(() => filterTokens(swapTokens), [filterTokens, swapTokens]);

  // The token being bought or sold cannot be its own counterpart
  const screenTokenSlug = tradeDirection === 'buy' ? tokenOutSlug : tradeDirection === 'sell' ? tokenInSlug : undefined;

  // While searching, the browser keeps its sections and lists every match in the order of the search ranking
  const tradeQuery = debouncedSearchValue.trim();
  const tradeSections = useMemo(() => {
    if (!tradeDirection) return undefined;

    const matches = tradeQuery ? findTokensByQuery(lang, swapTokensWithFilter, tradeQuery, importedSlugs) : undefined;

    return buildTradeSections({
      direction: tradeDirection,
      category,
      screenTokenSlug,
      userTokens: tradeQuery
        ? findTokensByQuery(lang, userTokensWithFilter, tradeQuery, importedSlugs)
        : userTokensWithFilter,
      popularTokens: matches ?? popularTokensWithFilter,
      swapTokens: matches ?? swapTokensWithFilter,
      isStablecoin: getIsStablecoin,
      isSearch: Boolean(matches),
    });
  }, [
    tradeDirection, category, screenTokenSlug, userTokensWithFilter, popularTokensWithFilter, swapTokensWithFilter,
    tradeQuery, lang, importedSlugs,
  ]);

  // "Pay With" offers the owned tokens only, so the search is limited to them as well
  const ownedTokens = useMemo(
    () => userTokensWithFilter.filter(({ amount, slug }) => amount > 0n && slug !== screenTokenSlug),
    [userTokensWithFilter, screenTokenSlug],
  );

  const filteredTokenList = useMemo(() => {
    const tokensToFilter = tradeDirection === 'buy'
      ? ownedTokens
      : shouldUseSwapTokens ? swapTokensWithFilter : allTokens;
    const enabledTokens = tokensToFilter.filter(({ isDisabled, slug }) => !isDisabled && slug !== screenTokenSlug);

    return debouncedSearchValue
      ? findTokensByQuery(lang, enabledTokens, debouncedSearchValue, importedSlugs)
      : enabledTokens;
  }, [
    allTokens, ownedTokens, tradeDirection, screenTokenSlug, shouldUseSwapTokens, debouncedSearchValue,
    swapTokensWithFilter, lang, importedSlugs,
  ]);

  const visibleFiatCurrencies = useMemo(() => {
    if (!fiatCurrencies.length || (category !== 'all' && category !== 'fiat')) {
      return EMPTY_ARRAY;
    }

    const query = debouncedSearchValue.trim().toLowerCase();
    if (!query) {
      return fiatCurrencies;
    }

    return fiatCurrencies.filter((currency) => (
      currency.toLowerCase().includes(query) || lang(CURRENCIES[currency].name).toLowerCase().includes(query)
    ));
  }, [fiatCurrencies, category, debouncedSearchValue, lang]);

  const areCategoriesShown = tradeSections !== undefined && (
    tradeDirection === 'sell' || ownedTokens.length > MIN_OWNED_TOKENS_FOR_CATEGORIES
  );

  const resetSearch = () => {
    setSearchValue('');
  };

  useSyncEffect(() => {
    setIsResetButtonVisible(Boolean(searchValue.length));

    const isValidAddress = !!getImportChainByAddress(searchValue, availableChains);
    const hasSearchResults = tradeSections
      ? Boolean(
        tradeSections.my.length || tradeSections.stablecoins.length || tradeSections.tokens.length
        || visibleFiatCurrencies.length,
      )
      : filteredTokenList.length !== 0 || visibleFiatCurrencies.length !== 0;
    let newRenderingKey = SearchState.Initial;

    if (isLoading && isValidAddress) {
      newRenderingKey = SearchState.Loading;
    } else if (token && isValidAddress) {
      newRenderingKey = SearchState.TokenByAddress;
    } else if (debouncedSearchValue.length && hasSearchResults) {
      newRenderingKey = SearchState.Search;
    } else if (!hasSearchResults) {
      newRenderingKey = SearchState.Empty;
    }

    setRenderingKey(newRenderingKey);

    if (newRenderingKey !== SearchState.Initial) {
      setSearchTokenList(filteredTokenList);
    }
  }, [
    searchTokenList.length, isLoading, searchValue, debouncedSearchValue, token, filteredTokenList,
    visibleFiatCurrencies, availableChains, tradeSections,
  ]);

  useEffect(() => {
    const chain = getImportChainByAddress(searchValue, availableChains);
    if (chain) {
      importToken({ chain, address: searchValue });
      setRenderingKey(SearchState.Loading);
    } else {
      resetImportToken();
    }
  }, [searchValue, availableChains]);

  useLayoutEffect(() => {
    if (!isActive || !scrollContainerRef.current) return;

    scrollContainerRef.current.scrollTop = 0;
  }, [isActive]);

  const handleTokenClick = useLastCallback((selectedToken: TokenType) => {
    searchInputRef.current?.blur();

    onTokenSelect(selectedToken);

    resetSearch();

    onBack();
  });

  const handleFiatClick = useLastCallback((currency: ApiBaseCurrency) => {
    searchInputRef.current?.blur();

    onFiatSelect?.(currency);

    resetSearch();

    onBack();
  });

  const handleOpenSettings = useLastCallback(() => {
    onClose();
    openSettingsWithState({ state: SettingsState.Assets });
  });

  function renderSearch() {
    return (
      <div
        className={buildClassName(styles.tokenSelectSearchWrapper, isTradeMode && styles.tokenSelectSearchWrapperTrade)}
      >
        <div
          className={buildClassName(
            styles.tokenSelectInputWrapper,
            isTradeMode && styles.tokenSelectInputWrapperTrade,
            searchClassName,
          )}
        >
          <i className={buildClassName(styles.tokenSelectSearchIcon, 'icon-search')} aria-hidden />
          <input
            ref={searchInputRef}
            name="token-search-modal"
            className={styles.tokenSelectInput}
            onChange={(e) => setSearchValue(e.target.value)}
            placeholder={lang(isTradeMode ? 'Search' : 'Name or Address...')}
            value={searchValue}
          />
          <Transition
            name="fade"
            activeKey={isResetButtonVisible ? 0 : 1}
            className={styles.tokenSelectSearchResetWrapper}
          >
            {isResetButtonVisible && (
              <button
                type="button"
                className={styles.tokenSelectSearchReset}
                aria-label={lang('Clear')}
                onClick={resetSearch}
              >
                <i className={buildClassName(styles.tokenSelectSearchResetIcon, 'icon-close')} aria-hidden />
              </button>
            )}
          </Transition>
        </div>
      </div>
    );
  }

  function renderToken(currentToken: TokenType) {
    const isAvailable = Boolean(!shouldFilter || currentToken.canSwap);
    // The trade browser shows the chain as a label next to the name, so the network line is left out
    const descriptionText = !isAvailable
      ? lang('Unavailable')
      : isTradeMode ? undefined : getChainNetworkName(currentToken.chain);

    const valueText = Number(currentToken.totalValue) > 0
      ? formatCurrency(currentToken.totalValue, shortBaseSymbol)
      : currentToken.price === 0
        ? lang('No Price')
        : lang('$token_price_value', { value: formatCurrency(currentToken.price, shortBaseSymbol, undefined, true) });

    return (
      <Token
        key={currentToken.slug}
        isAvailable={isAvailable}
        isSensitiveDataHidden={isSensitiveDataHidden}
        isTradeMode={isTradeMode}
        withChainIcon
        descriptionText={descriptionText}
        token={currentToken}
        valueText={valueText}
        onSelect={handleTokenClick}
      />
    );
  }

  function renderTokenGroup(tokens: TokenType[], title: string, shouldShowSettings?: boolean) {
    return (
      <div className={buildClassName(styles.tokenGroupContainer, isTradeMode && styles.tokenGroupContainerTrade)}>
        <div className={buildClassName(styles.tokenGroupHeader, isTradeMode && styles.tokenGroupHeaderTrade)}>
          <span className={buildClassName(styles.tokenGroupTitle, isTradeMode && styles.tokenGroupTitleAccent)}>
            {title}
          </span>
          {shouldShowSettings && (
            <span
              className={styles.tokenGroupAdditionalTitle}
              onClick={handleOpenSettings}
            >
              {lang('Settings')}
            </span>
          )}
        </div>
        {tokens.map(renderToken)}
      </div>
    );
  }

  function renderTradeGroup(tokens: TokenType[], title?: string) {
    if (!tokens.length) return undefined;

    return title ? renderTokenGroup(tokens, title) : renderAllTokens(tokens);
  }

  function renderFiatGroup() {
    if (!visibleFiatCurrencies.length) return undefined;

    return (
      <div className={buildClassName(styles.tokenGroupContainer, styles.tokenGroupContainerTrade)}>
        <div className={buildClassName(styles.tokenGroupHeader, styles.tokenGroupHeaderTrade)}>
          <span className={buildClassName(styles.tokenGroupTitle, styles.tokenGroupTitleAccent)}>{lang('Fiat')}</span>
        </div>
        {visibleFiatCurrencies.map((currency) => (
          <FiatCurrencyRow
            key={currency}
            currency={currency}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            onSelect={handleFiatClick}
          />
        ))}
      </div>
    );
  }

  function renderAllTokens(tokens: TokenType[]) {
    return (
      <div className={buildClassName(styles.tokenGroupContainer, isTradeMode && styles.tokenGroupContainerTrade)}>
        {tokens.map(renderToken)}
      </div>
    );
  }

  function renderTokenSkeleton() {
    return (
      <div className={buildClassName(styles.tokenContainer, styles.tokenContainerDisabled)}>
        <div className={styles.tokenLogoContainer}>
          <div className={styles.logoContainer}>
            <div className={styles.tokenLogoSkeleton} />
            <div className={styles.tokenNetworkLogoSkeleton} />
          </div>
          <div className={styles.nameContainer}>
            <span className={styles.tokenNameSkeleton} />
            <span className={styles.tokenValueSkeleton} />
          </div>
        </div>
        <div className={styles.tokenPriceContainer}>
          <span className={buildClassName(styles.tokenNameSkeleton, styles.rotateSkeleton)} />
          <span className={styles.tokenValueSkeleton} />
        </div>
      </div>
    );
  }

  function renderNotFound(shouldPlay: boolean) {
    return (
      <div className={styles.tokenNotFound}>
        <AnimatedIconWithPreview
          play={shouldPlay}
          tgsUrl={ANIMATED_STICKERS_PATHS.noData}
          previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
          size={ANIMATED_STICKER_MIDDLE_SIZE_PX}
          noLoop={false}
          nonInteractive
        />
        <span className={styles.tokenNotFoundTitle}>{lang(error ?? 'Not Found')}</span>
        <span className={styles.tokenNotFoundDesc}>{lang('Try another keyword or address.')}</span>
      </div>
    );
  }

  function renderSearchResults(tokenToImport?: TokenType) {
    if (tokenToImport) {
      return (
        <div className={styles.tokenGroupContainer}>
          {renderToken(tokenToImport)}
        </div>
      );
    }

    return (
      <>
        {renderTokenSkeleton()}
        {renderTokenSkeleton()}
        {renderTokenSkeleton()}
        {renderTokenSkeleton()}
        {renderTokenSkeleton()}
      </>
    );
  }

  function renderTokenGroups() {
    if (tradeSections) {
      const myGroup = renderTradeGroup(tradeSections.my, lang('My'));

      if (tradeDirection === 'buy') {
        return (
          <>
            {renderFiatGroup()}
            {myGroup}
          </>
        );
      }

      return (
        <>
          {myGroup}
          {renderFiatGroup()}
          {renderTradeGroup(tradeSections.stablecoins, lang('Stablecoins'))}
          {/* The remaining search matches go without a title, as in the native apps */}
          {renderTradeGroup(tradeSections.tokens, tradeQuery ? undefined : lang('Tokens'))}
        </>
      );
    }

    return (
      <>
        {!shouldHideMyTokens && renderTokenGroup(userTokensWithFilter, lang('MY'), true)}
        {renderTokenGroup(popularTokensWithFilter, lang('Popular'))}
      </>
    );
  }

  function renderContent(isContentActive: boolean, isFrom: boolean, currentKey: SearchState) {
    switch (currentKey) {
      case SearchState.Initial:
        return renderTokenGroups();
      case SearchState.Loading:
        return renderSearchResults();
      case SearchState.Search:
        return isTradeMode ? renderTokenGroups() : renderAllTokens(searchTokenList);
      case SearchState.TokenByAddress:
        return renderSearchResults(token);
      case SearchState.Empty:
        return renderNotFound(isContentActive);
    }
  }

  return (
    <>
      {!noHeader && (
        <ModalHeader
          title={lang(isTradeMode ? (tradeDirection === 'buy' ? 'Pay With' : 'You Receive') : 'Select Token')}
          onBackButtonClick={onBack}
          onClose={onClose}
        />
      )}

      <div
        ref={scrollContainerRef}
        className={buildClassName(styles.tokenSelectContent, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {renderSearch()}
        {areCategoriesShown && <CategoryTabs isActive={isActive} category={category} onChange={setCategory} />}
        <Transition name="fade" activeKey={renderingKey}>
          {renderContent}
        </Transition>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global, ownProps): StateProps => {
  const { baseCurrency, isSensitiveDataHidden } = global.settings;
  const { isLoading, token, error } = global.settings.importToken ?? {};
  const { tokenInSlug, tokenOutSlug } = global.currentSwap ?? {};
  const { swapVersion } = global;
  const pairsBySlug = global.swapPairs?.bySlug;
  const userTokens = selectAvailableUserForSwapTokens(global, ownProps.isSwapOut);
  const popularTokens = selectPopularTokens(global);
  const swapTokens = selectSwapTokens(global);
  const availableChains = selectCurrentAccount(global)?.byChain;
  const importedSlugs = selectCurrentAccountSettings(global)?.importedSlugs;

  return {
    baseCurrency,
    currencyRates: global.currencyRates,
    isLoading,
    token,
    error,
    pairsBySlug,
    swapVersion,
    tokenInSlug,
    tokenOutSlug,
    userTokens,
    popularTokens,
    swapTokens,
    availableChains,
    importedSlugs,
    isSensitiveDataHidden,
  };
})(TokenSelector));

function Token({
  token,
  isAvailable,
  isSensitiveDataHidden,
  isTradeMode,
  withChainIcon,
  descriptionText,
  valueText,
  onSelect,
}: {
  token: TokenType;
  isAvailable: boolean;
  isSensitiveDataHidden?: true;
  isTradeMode?: boolean;
  withChainIcon: boolean;
  descriptionText?: string;
  valueText: TeactNode;
  onSelect: (token: TokenType) => void;
}) {
  const lang = useLang();

  const handleClick = isAvailable ? () => onSelect(token) : undefined;
  const tokenName = getTokenName(lang, token);

  return (
    <div
      className={buildClassName(
        styles.tokenContainer,
        isTradeMode && styles.tokenContainerTrade,
        !isAvailable && styles.tokenContainerDisabled,
      )}
      onClick={handleClick}
    >
      <div className={styles.tokenLogoContainer}>
        <TokenIcon
          token={token}
          withChainIcon={withChainIcon}
          size={isTradeMode ? 'large' : undefined}
          className={!isAvailable ? styles.tokenLogoDisabled : undefined}
        />

        <div className={styles.nameContainer}>
          <TokenTitle
            tokenName={tokenName}
            tokenLabel={token.label}
            isRwaStock={getIsRwaStockToken(token)}
            isDisabled={!isAvailable}
          />
          {descriptionText && (
            <span
              className={buildClassName(
                styles.tokenNetwork,
                !isAvailable && styles.tokenTextDisabled,
              )}
            >
              {descriptionText}
            </span>
          )}
        </div>
      </div>
      <div className={buildClassName(styles.tokenPriceContainer, isTradeMode && styles.tokenPriceContainerTrade)}>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          min={4}
          max={10}
          seed={token.slug}
          rows={2}
          cellSize={8}
          align="right"
          className={buildClassName(
            styles.tokenAmount,
            !isAvailable && styles.tokenTextDisabled,
          )}
        >
          {formatCurrency(toDecimal(token.amount, token?.decimals), token.symbol)}
        </SensitiveData>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          min={4}
          max={10}
          seed={token.slug}
          rows={2}
          cellSize={8}
          align="right"
          className={buildClassName(
            styles.tokenValue,
            !isAvailable && styles.tokenTextDisabled,
          )}
        >
          {valueText}
        </SensitiveData>
      </div>
    </div>
  );
}

interface FiatCurrencyRowProps {
  currency: ApiBaseCurrency;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  onSelect: (currency: ApiBaseCurrency) => void;
}

const FiatCurrencyRow = memo(({
  currency,
  baseCurrency,
  currencyRates,
  onSelect,
}: FiatCurrencyRowProps) => {
  const lang = useLang();

  // The rates are per US dollar, so one unit of the currency costs the inverse of its rate
  const rate = Number(currencyRates[currency]);
  const price = rate ? calculateTokenPrice(1 / rate, baseCurrency, currencyRates) : 0;
  const priceText = price
    ? lang('$token_price_value', {
      value: formatCurrency(price, getShortCurrencySymbol(baseCurrency), undefined, true),
    })
    : lang('No Price');

  return (
    <div
      className={buildClassName(styles.tokenContainer, styles.tokenContainerTrade)}
      onClick={() => onSelect(currency)}
    >
      <div className={styles.tokenLogoContainer}>
        <FiatCurrencyIcon currency={currency} size="large" />
        <div className={styles.nameContainer}>
          <TokenTitle tokenName={lang(CURRENCIES[currency].name)} />
        </div>
      </div>
      <div className={buildClassName(styles.tokenPriceContainer, styles.tokenPriceContainerTrade)}>
        <span className={styles.tokenAmount}>{formatCurrency(0, currency)}</span>
        <span className={styles.tokenValue}>{priceText}</span>
      </div>
    </div>
  );
});

interface CategoryTabsProps {
  isActive?: boolean;
  category: TradeCategory;
  onChange: (value: TradeCategory) => void;
}

const CategoryTabs = memo(({ isActive, category, onChange }: CategoryTabsProps) => {
  const lang = useLang();

  const tabs = useMemo<TabWithProperties[]>(
    () => TRADE_CATEGORIES.map(({ title }, index) => ({ id: index, title: lang(title) })),
    [lang],
  );
  const activeTab = TRADE_CATEGORIES.findIndex(({ value }) => value === category);

  const handleSwitchTab = useLastCallback((index: number) => {
    onChange(TRADE_CATEGORIES[index].value);
  });

  return (
    <TabList
      isActive={isActive}
      tabs={tabs}
      activeTab={activeTab}
      className={styles.categoryTabs}
      overlayClassName={styles.categoryTabsOverlay}
      onSwitchTab={handleSwitchTab}
    />
  );
});

function getIsStablecoin(slug: string) {
  return getStablecoinSlugs().has(slug);
}

function filterAndSortTokens(
  tokens: TokenType[],
  availableChains: Partial<Record<ApiChain, unknown>>,
  tokenInSlug: string | undefined,
  pairsBySlug: Record<string, AssetPairs> | undefined,
  swapVersion: ApiSwapVersion,
) {
  if (!tokens.length || !tokenInSlug) return [];

  return tokens
    .map((token) => ({
      ...token,
      canSwap: isSwapPairValid(tokenInSlug, token.slug, pairsBySlug, swapVersion, availableChains),
    }))
    .sort((a, b) => Number(b.canSwap) - Number(a.canSwap));
}

function filterSupportedTokens<T extends TokenType>(
  tokens: T[],
  isFilterActive: boolean,
  availableChains: Partial<Record<ApiChain, unknown>>,
  selectedChains?: Set<ApiChain>,
): T[] {
  if (!isFilterActive && !selectedChains) {
    return tokens;
  }

  return tokens.filter((token) => {
    if (isFilterActive && !(token.chain in availableChains)) {
      return false;
    }

    return !selectedChains || selectedChains.has(token.chain as ApiChain);
  });
}

function getImportChainByAddress(address: string, availableChains: Partial<Record<ApiChain, unknown>>) {
  const availableChainsSupportingImport = Object.fromEntries(
    (Object.keys(availableChains) as ApiChain[])
      .filter((chain) => getChainConfig(chain).canImportTokens)
      .map((chain) => [chain, undefined]),
  ) as Record<ApiChain, unknown>;

  return getChainFromAddress(address, availableChainsSupportingImport);
}
