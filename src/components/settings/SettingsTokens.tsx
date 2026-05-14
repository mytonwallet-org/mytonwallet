import React, {
  memo, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiBaseCurrency } from '../../api/types';
import { SettingsState, type UserToken } from '../../global/types';

import { bigintMultiplyToNumber } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import getDeterministicRandom from '../../util/getDeterministicRandom';
import { buildCollectionByKey } from '../../util/iteratees';
import getTokenName from '../main/helpers/getTokenName';

import useInfiniteScroll from '../../hooks/useInfiniteScroll';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import TokenTitle from '../common/TokenTitle';
import DeleteTokenModal from '../main/modals/DeleteTokenModal';
import AnimatedCounter from '../ui/AnimatedCounter';
import InfiniteScroll from '../ui/InfiniteScroll';
import SensitiveData from '../ui/SensitiveData';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

const TOKEN_HEIGHT_REM = 4;
const TOKEN_ITEM_CLASS = 'settings-token-item';
const TOKEN_ITEM_SELECTOR = `.${TOKEN_ITEM_CLASS}`;
const SCROLL_CONTAINER_SELECTOR = '.custom-scroll';

interface OwnProps {
  isActive?: boolean;
  tokens?: UserToken[];
  pinnedSlugs?: string[];
  baseCurrency: ApiBaseCurrency;
  isSensitiveDataHidden?: true;
}

function SettingsTokens({
  isActive,
  tokens,
  baseCurrency,
  isSensitiveDataHidden,
  pinnedSlugs,
}: OwnProps) {
  const {
    openSettingsWithState,
    toggleTokenVisibility,
  } = getActions();
  const lang = useLang();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const [tokenToDelete, setTokenToDelete] = useState<UserToken | undefined>();

  const tokenSlugs = useMemo(() => tokens?.map(({ slug }) => slug), [tokens]);
  const tokensBySlug = useMemo(
    () => (tokens ? buildCollectionByKey(tokens, 'slug') : undefined),
    [tokens],
  );

  const [viewportSlugs, getMore] = useInfiniteScroll({
    listIds: tokenSlugs,
    isActive,
  });

  const viewportIndex = useMemo(() => (
    viewportSlugs && tokenSlugs ? tokenSlugs.indexOf(viewportSlugs[0]) : -1
  ), [tokenSlugs, viewportSlugs]);
  const visibleCount = viewportSlugs?.length ?? 0;
  const currentContainerHeight = visibleCount > 0 && viewportIndex >= 0
    ? (viewportIndex + visibleCount) * TOKEN_HEIGHT_REM
    : undefined;
  const containerStyle = currentContainerHeight !== undefined
    ? `height: ${currentContainerHeight}rem`
    : undefined;
  const maxHeight = currentContainerHeight !== undefined
    ? `${currentContainerHeight}rem`
    : undefined;

  const handleDeleteTokenModalClose = useLastCallback(() => {
    setTokenToDelete(undefined);
  });

  const handleOpenAddTokenPage = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.SelectTokenList });
  });

  const handleOpenAddTokenPageKeyDown = useLastCallback((e: React.KeyboardEvent) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      stopEvent(e);
      handleOpenAddTokenPage();
    }
  });

  const handleTokenVisibility = useLastCallback((
    token: UserToken,
    e: React.MouseEvent | React.TouchEvent | React.KeyboardEvent,
  ) => {
    stopEvent(e);
    toggleTokenVisibility({ slug: token.slug, shouldShow: Boolean(token.isDisabled) });
  });

  const handleTokenKeyDown = useLastCallback((token: UserToken, e: React.KeyboardEvent) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      handleTokenVisibility(token, e);
    }
  });

  const handleDeleteToken = useLastCallback((token: UserToken, e: React.MouseEvent<HTMLSpanElement>) => {
    e.stopPropagation();
    setTokenToDelete(token);
  });

  function renderToken(token: UserToken, indexInViewport: number) {
    const {
      symbol, amount, price, slug, isDisabled,
    } = token;

    const globalIndex = viewportIndex + indexInViewport;
    const topOffset = globalIndex * TOKEN_HEIGHT_REM;

    const totalAmount = bigintMultiplyToNumber(amount, price);
    const isPinned = pinnedSlugs?.includes(slug);
    const tokenName = getTokenName(lang, token);

    const isDeleteButtonVisible = amount === 0n;

    const ariaLabel = isDisabled
      ? `${lang('Show')} ${tokenName}`
      : `${lang('Hide')} ${tokenName}`;

    return (
      <div
        key={slug}
        tabIndex={0}
        role="button"
        aria-label={ariaLabel}
        aria-pressed={!isDisabled}
        style={`top: ${topOffset}rem`}
        className={buildClassName(styles.item, styles.item_token, TOKEN_ITEM_CLASS)}
        onKeyDown={(e) => handleTokenKeyDown(token, e)}
        onClick={(e) => handleTokenVisibility(token, e)}
      >
        <TokenIcon token={token} withChainIcon />
        <div className={styles.tokenInfo}>
          <TokenTitle
            tokenName={tokenName}
            tokenLabel={token.label}
            isPinned={isPinned}
          />
          <div className={styles.tokenDescription}>
            <SensitiveData
              isActive={isSensitiveDataHidden}
              cols={getDeterministicRandom(4, 9, globalIndex)}
              rows={2}
              cellSize={8}
              contentClassName={styles.tokenAmount}
            >
              <AnimatedCounter text={formatCurrency(toDecimal(totalAmount, token.decimals, true), shortBaseSymbol)} />
              <i className={styles.dot} aria-hidden />
              <AnimatedCounter text={formatCurrency(toDecimal(amount, token.decimals), symbol)} />
            </SensitiveData>
            {isDeleteButtonVisible && (
              <>
                <i className={styles.dot} aria-hidden />
                <span className={styles.deleteText} onClick={(e) => handleDeleteToken(token, e)}>
                  {lang('Delete')}
                </span>
              </>
            )}
          </div>
        </div>
        <Switcher
          className={styles.menuSwitcher}
          checked={!isDisabled}
        />
      </div>
    );
  }

  return (
    <>
      <p className={styles.blockTitle}>{lang('My Assets')}</p>
      <div className={styles.settingsBlock}>
        <div
          role="button"
          tabIndex={0}
          className={buildClassName(styles.item, styles.item_small)}
          onClick={handleOpenAddTokenPage}
          onKeyDown={handleOpenAddTokenPageKeyDown}
        >
          <span className={styles.itemTitle}>{lang('Add Token')}</span>
          <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
        </div>

        <InfiniteScroll
          className={styles.tokenList}
          items={viewportSlugs}
          itemSelector={TOKEN_ITEM_SELECTOR}
          withAbsolutePositioning
          scrollContainerClosest={SCROLL_CONTAINER_SELECTOR}
          maxHeight={maxHeight}
          style={containerStyle}
          onLoadMore={getMore}
        >
          {viewportSlugs?.map((slug, i) => renderToken(tokensBySlug![slug], i))}
        </InfiniteScroll>
      </div>

      <DeleteTokenModal token={tokenToDelete} onClose={handleDeleteTokenModalClose} />
    </>
  );
}

export default memo(SettingsTokens);
