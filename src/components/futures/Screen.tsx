import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useScrolledState from '../../hooks/useScrolledState';

import BackHeader from '../common/BackHeader';

import styles from './Futures.module.scss';

interface OwnProps {
  title: TeactNode;
  bodyClassName?: string;
  /** Stays in place over the scrolling body */
  overlay?: TeactNode;
  children: TeactNode;
  onBackClick: NoneToVoidFunction;
}

function Screen({
  title, bodyClassName, overlay, children, onBackClick,
}: OwnProps) {
  const { isScrolled, handleScroll } = useScrolledState();

  return (
    <div className={styles.screen}>
      <BackHeader title={title} withNotchOnScroll isScrolled={isScrolled} onBackClick={onBackClick} />
      <div className={buildClassName(styles.body, 'custom-scroll', bodyClassName)} onScroll={handleScroll}>
        {children}
      </div>
      {overlay}
    </div>
  );
}

export default Screen;
