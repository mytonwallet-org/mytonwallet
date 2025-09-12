import React, {
  type ElementRef,
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiBaseCurrency } from '../../api/types';
import { SettingsState, type UserToken } from '../../global/types';

import { DEFAULT_ENABLED_TOKEN_SLUGS } from '../../config';
import { bigintMultiplyToNumber } from '../../util/bigint';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import { isBetween } from '../../util/math';

import useEffectOnce from '../../hooks/useEffectOnce';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import DeleteTokenModal from '../main/modals/DeleteTokenModal';
import AnimatedCounter from '../ui/AnimatedCounter';
import Draggable from '../ui/Draggable';
import SensitiveData from '../ui/SensitiveData';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

interface SortState {
  orderedTokenSlugs?: string[];
  dragOrderTokenSlugs?: string[];
  draggedIndex?: number;
}

interface OwnProps {
  parentContainer: ElementRef<HTMLDivElement>;
  tokens?: UserToken[];
  orderedSlugs?: string[];
  isSortByValueEnabled?: boolean;
  baseCurrency?: ApiBaseCurrency;
  withChainIcon?: boolean;
  isSensitiveDataHidden?: true;
}

const TOKEN_HEIGHT_PX = 64;
const TOP_OFFSET = 48;

function SettingsTokens({
  parentContainer,
  tokens,
  orderedSlugs,
  isSortByValueEnabled,
  baseCurrency,
  withChainIcon,
  isSensitiveDataHidden,
}: OwnProps) {
  const {
    openSettingsWithState,
    updateOrderedSlugs,
    rebuildOrderedSlugs,
    toggleTokenVisibility,
  } = getActions();
  const lang = useLang();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  const tokensRef = useRef<HTMLDivElement>();
  const sortableContainerRef = useRef<HTMLDivElement>();

  const [tokenToDelete, setTokenToDelete] = useState<UserToken | undefined>();
  const [state, setState] = useState<SortState>({
    orderedTokenSlugs: orderedSlugs,
    dragOrderTokenSlugs: orderedSlugs,
    draggedIndex: undefined,
  });

  useEffectOnce(() => {
    rebuildOrderedSlugs();
  });

  useEffect(() => {
    if (!arraysAreEqual(orderedSlugs, state.orderedTokenSlugs)) {
      setState({
        orderedTokenSlugs: orderedSlugs,
        dragOrderTokenSlugs: orderedSlugs,
        draggedIndex: undefined,
      });
    }
  }, [orderedSlugs, state.orderedTokenSlugs]);

  const handleOpenAddTokenPage = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.SelectTokenList });
  });

  const handleDrag = useLastCallback((translation: { x: number; y: number }, id: string | number) => {
    const delta = Math.round(translation.y / TOKEN_HEIGHT_PX);
    const index = state.orderedTokenSlugs?.indexOf(id as string) ?? 0;
    const dragOrderTokenSlugs = state.orderedTokenSlugs?.filter((tokenSlug) => tokenSlug !== id);

    if (!dragOrderTokenSlugs || !isBetween(index + delta, 0, orderedSlugs?.length ?? 0)) {
      return;
    }

    dragOrderTokenSlugs.splice(index + delta, 0, id as string);
    setState((current) => ({
      ...current,
      draggedIndex: index,
      dragOrderTokenSlugs,
    }));
  });

  const handleDragEnd = useLastCallback(() => {
    setState((current) => {
      updateOrderedSlugs({
        orderedSlugs: current.dragOrderTokenSlugs!,
      });

      return {
        ...current,
        orderedTokenSlugs: current.dragOrderTokenSlugs,
        draggedIndex: undefined,
      };
    });
  });

  const handleTokenVisibility = useLastCallback((token: UserToken, e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    e.stopPropagation();
    toggleTokenVisibility({ slug: token.slug, shouldShow: Boolean(token.isDisabled) });
  });

  const handleDeleteToken = useLastCallback((token: UserToken, e: React.MouseEvent<HTMLSpanElement>) => {
    e.stopPropagation();
    setTokenToDelete(token);
  });

  function renderToken(token: UserToken, index: number) {
    const {
      symbol, name, amount, price, slug, isDisabled,
    } = token;

    const totalAmount = bigintMultiplyToNumber(amount, price);
    const isDragged = state.draggedIndex === index;

    const draggedTop = isSortByValueEnabled ? getOffsetByIndex(index) : getOffsetBySlug(slug, state.orderedTokenSlugs);
    const top = isSortByValueEnabled ? getOffsetByIndex(index) : getOffsetBySlug(slug, state.dragOrderTokenSlugs);

    const style = `top: ${isDragged ? draggedTop : top}px;`;
    const knobStyle = 'left: 1rem;';

    const isDeleteButtonVisible = amount === 0n
      && !Object.values(DEFAULT_ENABLED_TOKEN_SLUGS).some((tokenSlugs) => tokenSlugs.includes(slug));

    const isDragDisabled = isSortByValueEnabled || tokens!.length <= 1;

    return (
      <Draggable
        key={slug}
        id={slug}
        onDrag={handleDrag}
        onDragEnd={handleDragEnd}
        style={style}
        knobStyle={knobStyle}
        isDisabled={isDragDisabled}
        className={buildClassName(styles.item, styles.item_token, !isSortByValueEnabled && styles.draggable)}
        offset={{ top: TOP_OFFSET }}
        parentRef={tokensRef}
        scrollRef={parentContainer}

        onClick={(e) => handleTokenVisibility(token, e)}
      >
        <TokenIcon token={token} withChainIcon={withChainIcon} />
        <div className={styles.tokenInfo}>
          <div className={styles.tokenTitle}>
            {name}
          </div>
          <div className={styles.tokenDescription}>
            <SensitiveData
              isActive={isSensitiveDataHidden}
              cols={4 + (top % 6)}
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
      </Draggable>
    );
  }

  return (
    <>
      <p className={styles.blockTitle}>{lang('My Tokens')}</p>
      <div className={styles.contentRelative} ref={sortableContainerRef}>
        <div
          className={buildClassName(styles.settingsBlock, styles.sortableContainer)}
          style={`height: ${(tokens?.length ?? 0) * TOKEN_HEIGHT_PX + TOP_OFFSET}px`}
          ref={tokensRef}
        >
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleOpenAddTokenPage}>
            {lang('Add Token')}
            <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
          </div>

          {tokens?.map(renderToken)}
        </div>
      </div>

      <DeleteTokenModal token={tokenToDelete} />
    </>
  );
}

function arraysAreEqual<T>(arr1: T[] = [], arr2: T[] = []) {
  return arr1.length === arr2.length && arr1.every((value, index) => value === arr2[index]);
}

function getOffsetBySlug(slug: string, list: string[] = []) {
  const realIndex = list.indexOf(slug);
  const index = realIndex === -1 ? list.length : realIndex;
  return getOffsetByIndex(index);
}

function getOffsetByIndex(index: number) {
  return index * TOKEN_HEIGHT_PX + TOP_OFFSET;
}

export default memo(SettingsTokens);
