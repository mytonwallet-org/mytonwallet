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
  children?: TeactNode;
}

function TokenListItem({
  topOffset,
  withAnimation,
  shouldFadeInPlace,
  children,
}: OwnProps) {
  const { ref: animationRef } = useListItemAnimation(styles, withAnimation, topOffset, shouldFadeInPlace);

  return (
    <div
      ref={animationRef}
      style={`top: ${topOffset}rem`}
      className={buildClassName('token-list-item', styles.listItem)}
    >
      {children}
    </div>
  );
}

export default TokenListItem;
