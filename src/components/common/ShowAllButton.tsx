import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import { formatNumber } from '../../util/formatNumber';
import { toNativeDigits } from '../../util/nativeDigits';

import Button from '../ui/Button';

import styles from './ShowAllButton.module.scss';

interface OwnProps {
  /** The class of the font icon, such as `icon-show-all` */
  icon: string;
  label: string;
  /** The number in the badge after the label. The badge hides at zero. */
  amount?: number;
  /** Pins the button to the bottom of its card, above the scrolled list, with a blurred background */
  isFloating?: boolean;
  testId?: string;
  onClick: NoneToVoidFunction;
}

function ShowAllButton({
  icon, label, amount, isFloating, testId, onClick,
}: OwnProps) {
  return (
    <Button
      isSimple
      className={buildClassName(styles.root, isFloating && styles.floating)}
      testId={testId}
      onClick={onClick}
    >
      <i className={buildClassName(styles.icon, icon)} aria-hidden />
      <span className={styles.label}>{label}</span>
      {Boolean(amount) && <span className={styles.badge}>{toNativeDigits(formatNumber(amount))}</span>}
    </Button>
  );
}

export default memo(ShowAllButton);
