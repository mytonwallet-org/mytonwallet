import type { TeactNode } from '../../../../lib/teact/teact';
import React from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import useListItemAnimation from '../../../../hooks/useListItemAnimation';

import styles from './Assets.module.scss';

interface OwnProps {
  /** In rem */
  topOffset: number;
  withAnimation: boolean;
  shouldFadeInPlace?: boolean;
  isWidget?: boolean;
  children?: TeactNode;
}

function TokenListItem({
  topOffset,
  withAnimation,
  shouldFadeInPlace,
  isWidget,
  children,
}: OwnProps) {
  const { ref: animationRef } = useListItemAnimation(styles, withAnimation, topOffset, shouldFadeInPlace);

  return (
    <div
      ref={isWidget ? undefined : animationRef}
      style={isWidget ? undefined : `top: ${topOffset}rem`}
      className={buildClassName('token-list-item', isWidget ? styles.listItemCompact : styles.listItem)}
    >
      {children}
    </div>
  );
}

export default TokenListItem;
