import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';

import styles from './OverviewScrollButton.module.scss';

interface OwnProps {
  isVisible: boolean;
  direction: 'left' | 'right';
  onClick: (direction: 'left' | 'right') => void;
}

function OverviewScrollButton({ isVisible, direction, onClick }: OwnProps) {
  const lang = useLang();

  const isLeft = direction === 'left';

  const handleClick = useLastCallback(() => {
    onClick(direction);
  });

  return (
    <Button
      isSimple
      ariaLabel={lang(isLeft ? 'Scroll Left' : 'Scroll Right')}
      className={buildClassName(
        styles.button,
        isLeft ? styles.buttonLeft : styles.buttonRight,
        !isVisible && styles.hidden,
      )}
      onClick={handleClick}
    >
      <i
        className={buildClassName(styles.icon, isLeft ? 'icon-chevron-left-alt' : 'icon-chevron-right-alt')}
        aria-hidden
      />
    </Button>
  );
}

export default memo(OverviewScrollButton);
