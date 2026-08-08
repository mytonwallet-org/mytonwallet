import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiChain } from '../../api/types';
import type { ChainDisplay } from '../../global/selectors';

import { selectCurrentAccountChainDisplay } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { REM } from '../../util/windowEnvironment';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useSortableList from '../../hooks/useSortableList';

import Switcher from '../ui/Switcher';
import ChainRow from './ChainRow';
import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  chainDisplay?: ChainDisplay;
}

const CHAIN_ROW_HEIGHT_PX = 4 * REM;
const EMPTY_CHAINS: ApiChain[] = [];

function SettingsChains({
  isActive,
  chainDisplay,
  onBackClick,
}: OwnProps & StateProps) {
  const { toggleChainVisibility, setChainDisplayMode, updateChainDisplayOrder } = getActions();

  const lang = useLang();
  const listRef = useRef<HTMLDivElement>();
  const scrollRef = useRef<HTMLDivElement>();

  useHistoryBack({ isActive, onBack: onBackClick });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  const chains = chainDisplay?.orderedChains ?? EMPTY_CHAINS;
  const isSortedByValue = chainDisplay?.config.displayMode !== 'manual';
  const visibleChains = useMemo(() => new Set(chainDisplay?.visibleChains), [chainDisplay]);

  const handleOrderChange = useLastCallback((orderedChains: ApiChain[]) => {
    updateChainDisplayOrder({ orderedChains });
  });

  const { sortState, handleDrag, handleDragEnd } = useSortableList(chains, CHAIN_ROW_HEIGHT_PX, handleOrderChange);

  const handleSortModeClick = useLastCallback(() => {
    setChainDisplayMode({ displayMode: isSortedByValue ? 'manual' : 'value' });
  });

  const handleChainClick = useLastCallback((chain: ApiChain) => {
    const isVisible = visibleChains.has(chain);
    if (isSortedByValue || (isVisible && visibleChains.size <= 1)) {
      return;
    }

    toggleChainVisibility({ chain, shouldShow: !isVisible });
  });

  // Every row asks for its own position while a drag is in progress. Looking it up with `indexOf` would scan
  // the list once per row, so the positions are collected into maps beforehand and read by chain name.
  const orderedIndexMap = useMemo(() => new Map(sortState.orderedIds.map((id, index) => [id, index])), [sortState]);
  const dragOrderIndexMap = useMemo(() => new Map(sortState.dragOrderIds.map((id, index) => [id, index])), [sortState]);

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Blockchains')} isScrolled={isScrolled} onBackClick={onBackClick} />
      <div
        ref={scrollRef}
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        <div className={buildClassName(styles.settingsBlock, styles.settingsBlockWithDescription)}>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleSortModeClick}>
            <span className={styles.itemTitle}>{lang('Sort by Value')}</span>
            <Switcher
              className={styles.menuSwitcher}
              label={lang('Sort by Value')}
              checked={isSortedByValue}
            />
          </div>
        </div>
        <p className={styles.blockDescription}>
          {lang('Automatically sort and hide chains based on your portfolio.')}
        </p>

        <div
          ref={listRef}
          className={buildClassName(styles.settingsBlock, styles.settingsBlockWithDescription, styles.chainList)}
          style={buildStyle(`height: ${chains.length * CHAIN_ROW_HEIGHT_PX}px`)}
        >
          {chains.map((chain, index) => {
            const isVisible = visibleChains.has(chain);
            const isDragged = sortState.draggedIndex === index;
            const rowIndex = (isDragged ? orderedIndexMap : dragOrderIndexMap).get(chain) ?? index;

            return (
              <ChainRow
                key={chain}
                chain={chain}
                isVisible={isVisible}
                isDraggable={!isSortedByValue}
                isSwitcherDisabled={isSortedByValue || (isVisible && visibleChains.size <= 1)}
                top={rowIndex * CHAIN_ROW_HEIGHT_PX}
                parentRef={listRef}
                scrollRef={scrollRef}
                onDrag={handleDrag}
                onDragEnd={handleDragEnd}
                onToggle={handleChainClick}
              />
            );
          })}
        </div>
        <p className={styles.blockDescription}>
          {lang('Hidden chains will still be available to receive and send tokens, but won’t appear in the main list.')}
        </p>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    chainDisplay: selectCurrentAccountChainDisplay(global),
  };
})(SettingsChains));
