import type { ElementRef } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { ApiChain } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { getChainTitle } from '../../util/chain';
import getChainNetworkIcon from '../../util/swap/getChainNetworkIcon';

import useLastCallback from '../../hooks/useLastCallback';

import Draggable from '../ui/Draggable';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

interface OwnProps {
  chain: ApiChain;
  isVisible: boolean;
  isDraggable: boolean;
  isSwitcherDisabled: boolean;
  top: number;
  parentRef: ElementRef<HTMLDivElement>;
  scrollRef: ElementRef<HTMLDivElement>;
  onDrag: (translation: { x: number; y: number }, id: string | number) => void;
  onDragEnd: NoneToVoidFunction;
  onToggle: (chain: ApiChain) => void;
}

function ChainRow({
  chain,
  isVisible,
  isDraggable,
  isSwitcherDisabled,
  top,
  parentRef,
  scrollRef,
  onDrag,
  onDragEnd,
  onToggle,
}: OwnProps) {
  const title = getChainTitle(chain);

  const handleClick = useLastCallback(() => {
    onToggle(chain);
  });

  return (
    <Draggable
      id={chain}
      isDisabled={!isDraggable}
      isKnobDisabled={!isVisible}
      parentRef={parentRef}
      scrollRef={scrollRef}
      className={buildClassName(styles.chainRow, isDraggable && styles.chainRow_draggable)}
      style={buildStyle(`top: ${top}px`)}
      onClick={handleClick}
      onDrag={onDrag}
      onDragEnd={onDragEnd}
    >
      <div className={buildClassName(styles.item, styles.chainItem, !isDraggable && styles.chainItem_automatic)}>
        <img src={getChainNetworkIcon(chain)} alt="" className={styles.chainIcon} />
        <span className={styles.itemTitle}>{title}</span>
        <Switcher
          className={styles.menuSwitcher}
          label={title}
          checked={isVisible}
          isDisabled={isSwitcherDisabled}
        />
      </div>
    </Draggable>
  );
}

export default memo(ChainRow);
