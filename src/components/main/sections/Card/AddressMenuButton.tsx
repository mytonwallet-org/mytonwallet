import React, { memo } from '../../../../lib/teact/teact';

import buildClassName from '../../../../util/buildClassName';

import styles from './Card.module.scss';

interface OwnProps {
  title: string;
  withTextGradient?: boolean;
  isMinimized?: boolean;
  testId?: string;
  toggleMenu: NoneToVoidFunction;
  onMouseEnter?: NoneToVoidFunction;
  onMouseLeave?: NoneToVoidFunction;
}

function AddressMenuButton({
  title,
  withTextGradient,
  isMinimized,
  testId,
  toggleMenu,
  onMouseEnter,
  onMouseLeave,
}: OwnProps) {
  return (
    <button
      type="button"
      className={buildClassName(
        styles.address,
        isMinimized && styles.addressStatic,
        withTextGradient && 'gradientText',
      )}
      tabIndex={isMinimized ? -1 : undefined}
      data-testid={testId}
      onClick={toggleMenu}
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
    >
      <span className={styles.addressTitle}>{title}</span>
      {!isMinimized && <i className={buildClassName('icon-qr-code', styles.addressQrIcon)} aria-hidden />}
    </button>
  );
}

export default memo(AddressMenuButton);
