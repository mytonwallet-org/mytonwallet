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

import type { ApiBaseCurrency, ApiChain, ApiSwapVersion } from '../../api/types';
import {
  type AssetPairs, SettingsState, type UserSwapToken, type UserToken,
} from '../../global/types';

import { ANIMATED_STICKER_MIDDLE_SIZE_PX } from '../../config';
import {
  selectAvailableUserForSwapTokens,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectIsMultichainAccount,
  selectPopularTokens,
  selectSwapTokens,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig, getSupportedChains, getTrustedUsdtSlugs } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import { getChainFromAddress } from '../../util/isValidAddress';
import { disableSwipeToClose, enableSwipeToClose } from '../../util/modalSwipeManager';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import { isSwapPairValid } from '../../util/swap/isSwapPairValid';
import { getChainBySlug } from '../../util/tokens';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useSyncEffect from '../../hooks/useSyncEffect';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import ModalHeader from '../ui/ModalHeader';
import SensitiveData from '../ui/SensitiveData';
import Transition from '../ui/Transition';
import TokenIcon from './TokenIcon';
import TokenTitle from './TokenTitle';

import styles from './TokenSelector.module.scss';

type TokenType = UserToken | UserSwapToken;

type TokenSortFactors = {
  tickerExactMatch: number;
  tickerMatchLength: number;
  nameMatchLength: number;
  specialOrder: number;
};

interface OwnProps {
  isActive?: boolean;
  shouldFilter?: boolean;
  shouldUseSwapTokens?: boolean;
  shouldHideMyTokens?: boolean;
  shouldHideNotSupportedTokens?: boolean;
  isSwapOut?: boolean;
  selectedChain?: ApiChain | ApiChain[];
  header?: TeactNode;
  onClose: NoneToVoidFunction;
  onBack: NoneToVoidFunction;
  onTokenSelect: (token: TokenType) => void;
}

interface StateProps {
  token?: TokenType;
  userTokens?: TokenType[];
  popularTokens?: TokenType[];
  swapTokens?: UserSwapToken[];
  tokenInSlug?: string;
  pairsBySlug?: Record<string, AssetPairs>;
  swapVersion: ApiSwapVersion;
  baseCurrency: ApiBaseCurrency;
  isLoading?: boolean;
  error?: string;
  isMultichain: boolean;
  availableChains?: Partial<Record<ApiChain, unknown>>;
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

function TokenSelector({
  token: tokenProp,
  userTokens: userTokensProp = EMPTY_ARRAY,
  swapTokens = EMPTY_ARRAY,
  popularTokens: popularTokensProp = EMPTY_ARRAY,
  header,
  shouldFilter,
  shouldUseSwapTokens,
  baseCurrency,
  tokenInSlug,
  pairsBySlug,
  swapVersion,
  isActive,
  isLoading,
  error,
  shouldHideMyTokens,
  shouldHideNotSupportedTokens = false,
  isMultichain,
  availableChains = EMPTY_OBJECT,
  selectedChain,
  isSensitiveDataHidden,
  onTokenSelect,
  onBack,
  onClose,
}: OwnProps & StateProps) {
  const { importToken, resetImportToken, openSettingsWithState } = getActions();
  const lang = useLang();

  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const scrollContainerRef = useRef<HTMLDivElement>();
  const searchInputRef = useRef<HTMLInputElement>();

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
  const [isResetButtonVisible, setIsResetButtonVisible] = useState(false);
  const [renderingKey, setRenderingKey] = useState(SearchState.Initial);
  const [searchTokenList, setSearchTokenList] = useState<TokenType[]>([]);

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
    () => filterSupportedTokens(swapTokens, shouldHideNotSupportedTokens, availableChains, selectedChains),
    [swapTokens, shouldHideNotSupportedTokens, availableChains, selectedChains],
  );

  const popularTokens = useMemo(
    () => filterSupportedTokens(popularTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains),
    [popularTokensProp, shouldHideNotSupportedTokens, availableChains, selectedChains],
  );

  const userTokensWithFilter = useMemo(() => filterTokens(userTokens), [filterTokens, userTokens]);
  const popularTokensWithFilter = useMemo(() => filterTokens(popularTokens), [filterTokens, popularTokens]);
  const swapTokensWithFilter = useMemo(() => filterTokens(swapTokens), [filterTokens, swapTokens]);

  const filteredTokenList = useMemo(() => {
    const tokensToFilter = shouldUseSwapTokens ? swapTokensWithFilter : allTokens;
    const untrimmedSearchValue = searchValue.toLowerCase();
    const lowerCaseSearchValue = untrimmedSearchValue.trim();

    if (untrimmedSearchValue.length && !lowerCaseSearchValue.length) {
      return [];
    }

    const filteredTokens = tokensToFilter.filter(({
      name, symbol, keywords, isDisabled,
    }) => {
      if (isDisabled) {
        return false;
      }

      const isName = name.toLowerCase().includes(lowerCaseSearchValue);
      const isSymbol = symbol.toLowerCase().includes(lowerCaseSearchValue);
      const isKeyword = keywords?.some((key) => key.toLowerCase().includes(lowerCaseSearchValue));

      return isName || isSymbol || isKeyword;
    }) ?? [];

    const sortFactors = filteredTokens.reduce((acc, searchResultToken) => {
      const factors = {
        tickerExactMatch: 0,
        tickerMatchLength: 0,
        nameMatchLength: 0,
        specialOrder: 0, // The higher the value, the higher the position
      };

      const tokenSymbol = searchResultToken.symbol.toLowerCase();
      const tokenName = searchResultToken.name.toLowerCase();

      if (tokenSymbol === lowerCaseSearchValue) {
        factors.tickerExactMatch = 1;
      }

      if (tokenSymbol.includes(lowerCaseSearchValue)) {
        factors.tickerMatchLength = lowerCaseSearchValue.length;
      }

      if (tokenName.includes(lowerCaseSearchValue)) {
        factors.nameMatchLength = lowerCaseSearchValue.length;
      }

      if (getTrustedUsdtSlugs().has(searchResultToken.slug)) {
        const chain = getChainBySlug(searchResultToken.slug);
        const supportedChains = getSupportedChains();
        const chainPriority = supportedChains.indexOf(chain);
        if (chainPriority !== -1) {
          // Subtracting, because the lower chain index should have higher priority, and `specialOrder` expects higher
          // numbers for higher priority.
          factors.specialOrder = supportedChains.length - chainPriority;
        }
      }

      acc[searchResultToken.slug] = factors;

      return acc;
    }, {} as Record<string, TokenSortFactors>);

    return filteredTokens.sort((a, b) => {
      const factorA = sortFactors[a.slug];
      const factorB = sortFactors[b.slug];
      const comparisonResult = compareTokens(factorA, factorB);
      if (comparisonResult !== 0) return comparisonResult;

      return Number(b.amount - a.amount);
    });
  }, [allTokens, shouldUseSwapTokens, searchValue, swapTokensWithFilter]);

  const resetSearch = () => {
    setSearchValue('');
  };

  useSyncEffect(() => {
    setIsResetButtonVisible(Boolean(searchValue.length));

    const isValidAddress = !!getImportChainByAddress(searchValue, availableChains);
    let newRenderingKey = SearchState.Initial;

    if (isLoading && isValidAddress) {
      newRenderingKey = SearchState.Loading;
    } else if (token && isValidAddress) {
      newRenderingKey = SearchState.TokenByAddress;
    } else if (searchValue.length && filteredTokenList.length !== 0) {
      newRenderingKey = SearchState.Search;
    } else if (filteredTokenList.length === 0) {
      newRenderingKey = SearchState.Empty;
    }

    setRenderingKey(newRenderingKey);

    if (newRenderingKey !== SearchState.Initial) {
      setSearchTokenList(filteredTokenList);
    }
  }, [searchTokenList.length, isLoading, searchValue, token, filteredTokenList, availableChains]);

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

  const handleOpenSettings = useLastCallback(() => {
    onClose();
    openSettingsWithState({ state: SettingsState.Assets });
  });

  function renderSearch() {
    return (
      <div className={styles.tokenSelectInputWrapper}>
        <i className={buildClassName(styles.tokenSelectSearchIcon, 'icon-search')} aria-hidden />
        <input
          ref={searchInputRef}
          name="token-search-modal"
          className={styles.tokenSelectInput}
          onChange={(e) => setSearchValue(e.target.value)}
          placeholder={lang('Name or Address...')}
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
    );
  }

  function renderToken(currentToken: TokenType) {
    const isAvailable = Boolean(!shouldFilter || currentToken.canSwap);
    const withChainIcon = (isMultichain || !!shouldUseSwapTokens) && (!selectedChains || selectedChains.size > 1);
    const descriptionText = isAvailable
      ? getChainNetworkName(currentToken.chain)
      : lang('Unavailable');

    const tokenPrice = currentToken.price === 0
      ? lang('No Price')
      : formatCurrency(currentToken.price, shortBaseSymbol, undefined, true);

    return (
      <Token
        key={currentToken.slug}
        isAvailable={isAvailable}
        isSensitiveDataHidden={isSensitiveDataHidden}
        withChainIcon={withChainIcon}
        descriptionText={descriptionText}
        token={currentToken}
        tokenPrice={tokenPrice}
        onSelect={handleTokenClick}
      />
    );
  }

  function renderTokenGroup(tokens: TokenType[], title: string, shouldShowSettings?: boolean) {
    return (
      <div className={styles.tokenGroupContainer}>
        <div className={styles.tokenGroupHeader}>
          <span className={styles.tokenGroupTitle}>{title}</span>
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

  function renderAllTokens(tokens: TokenType[]) {
    return (
      <div className={styles.tokenGroupContainer}>
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
    return (
      <>
        {!shouldHideMyTokens && renderTokenGroup(userTokensWithFilter, lang('MY'), true)}
        {renderTokenGroup(popularTokensWithFilter, lang('POPULAR'))}
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
        return renderAllTokens(searchTokenList);
      case SearchState.TokenByAddress:
        return renderSearchResults(token);
      case SearchState.Empty:
        return renderNotFound(isContentActive);
    }
  }

  return (
    <>
      {header || (
        <ModalHeader
          title={lang('Select Token')}
          onBackButtonClick={onBack}
          onClose={onClose}
        />
      )}
      {renderSearch()}

      <div
        ref={scrollContainerRef}
        className={buildClassName(styles.tokenSelectContent, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
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
  const { tokenInSlug } = global.currentSwap ?? {};
  const { swapVersion } = global;
  const pairsBySlug = global.swapPairs?.bySlug;
  const userTokens = selectAvailableUserForSwapTokens(global, ownProps.isSwapOut);
  const popularTokens = selectPopularTokens(global);
  const swapTokens = selectSwapTokens(global);
  const isMultichain = selectIsMultichainAccount(global, selectCurrentAccountId(global)!);
  const availableChains = selectCurrentAccount(global)?.byChain;

  return {
    baseCurrency,
    isLoading,
    token,
    error,
    pairsBySlug,
    swapVersion,
    tokenInSlug,
    userTokens,
    popularTokens,
    swapTokens,
    isMultichain,
    availableChains,
    isSensitiveDataHidden,
  };
})(TokenSelector));

function Token({
  token,
  isAvailable,
  isSensitiveDataHidden,
  withChainIcon,
  descriptionText,
  tokenPrice,
  onSelect,
}: {
  token: TokenType;
  isAvailable: boolean;
  isSensitiveDataHidden?: true;
  withChainIcon: boolean;
  descriptionText: string;
  tokenPrice: string;
  onSelect: (token: TokenType) => void;
}) {
  const handleClick = isAvailable ? () => onSelect(token) : undefined;

  return (
    <div
      className={buildClassName(
        styles.tokenContainer,
        !isAvailable && styles.tokenContainerDisabled,
      )}
      onClick={handleClick}
    >
      <div className={styles.tokenLogoContainer}>
        <TokenIcon
          token={token}
          withChainIcon={withChainIcon}
          className={buildClassName(styles.tokenLogo, !isAvailable && styles.tokenLogoDisabled)}
        />

        <div className={styles.nameContainer}>
          <TokenTitle
            tokenName={token.name}
            tokenLabel={token.label}
            isDisabled={!isAvailable}
          />
          <span
            className={buildClassName(
              styles.tokenNetwork,
              !isAvailable && styles.tokenTextDisabled,
            )}
          >
            {descriptionText}
          </span>
        </div>
      </div>
      <div className={styles.tokenPriceContainer}>
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
        <span className={buildClassName(
          styles.tokenValue,
          !isAvailable && styles.tokenTextDisabled,
        )}
        >
          {tokenPrice}
        </span>
      </div>
    </div>
  );
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

function compareTokens(a: TokenSortFactors, b: TokenSortFactors) {
  if (a.specialOrder !== b.specialOrder) {
    return b.specialOrder - a.specialOrder;
  }
  if (a.tickerExactMatch !== b.tickerExactMatch) {
    return b.tickerExactMatch - a.tickerExactMatch;
  }
  if (a.tickerMatchLength !== b.tickerMatchLength) {
    return b.tickerMatchLength - a.tickerMatchLength;
  }
  return b.nameMatchLength - a.nameMatchLength;
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
