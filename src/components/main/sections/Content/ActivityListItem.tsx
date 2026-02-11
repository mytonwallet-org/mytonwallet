import type { TeactNode } from '../../../../lib/teact/teact';
import React from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import useListItemAnimation from '../../../../hooks/useListItemAnimation';

import styles from './Activities.module.scss';

interface OwnProps {
  /** In rem */
  topOffset: number;
  withAnimation: boolean;
  children?: TeactNode;
}

function ActivityListItem({
  topOffset,
  withAnimation,
  children,
}: OwnProps) {
  const { ref: animationRef } = useListItemAnimation(styles, withAnimation, topOffset);

  return (
    <div
      ref={animationRef}
      style={`top: ${topOffset}rem`}
      className={buildClassName('ListItem', styles.listItem)}
    >
      {children}
    </div>
  );
}

export default ActivityListItem;
