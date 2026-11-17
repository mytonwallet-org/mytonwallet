import React, { memo } from '../../lib/teact/teact';

import { loadChunk } from './helpers/loadChunk';

import useChunk from '../../hooks/useChunk';

import styles from './Futures.module.scss';

interface OwnProps {
  isActive?: boolean;
}

function LazyFutures({ isActive }: OwnProps) {
  const chunk = useChunk(loadChunk, true);

  // The section is a slide of a transition, so it needs an element while the chunk loads
  if (!chunk) return <div className={styles.root} />;

  return <chunk.Futures isActive={isActive} />;
}

export default memo(LazyFutures);
