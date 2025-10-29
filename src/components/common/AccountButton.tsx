import React, { memo } from '../../lib/teact/teact';

import type { ApiNft } from '../../api/types';
import type { AccountType } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { shortenAddress } from '../../util/shortenAddress';

import { useCachedImage } from '../../hooks/useCachedImage';
import useCardCustomization from '../../hooks/useCardCustomization';

import styles from './AccountButton.module.scss';

interface OwnProps {
  accountId: string;
  address: string;
  title?: string;
  accountType: AccountType;
  isActive?: boolean;
  isLoading?: boolean;
  ariaLabel?: string;
  className?: string;
  titleClassName?: string;
  withCheckbox?: boolean;
  cardBackgroundNft?: ApiNft;
  onClick?: NoneToVoidFunction;
}

const ACCOUNT_WITH_ICON_ADDRESS_SHIFT = 3;
const ACCOUNT_ADDRESS_SHIFT = 4;

function AccountButton({
  accountId,
  address,
  title,
  accountType,
  ariaLabel,
  isActive,
  isLoading,
  className,
  titleClassName,
  withCheckbox,
  cardBackgroundNft,
  onClick,
}: OwnProps) {
  const {
    backgroundImageUrl,
    withTextGradient,
    classNames: mtwCardClassNames,
  } = useCardCustomization(cardBackgroundNft);
  const { imageUrl } = useCachedImage(backgroundImageUrl);

  const isHardware = accountType === 'hardware';
  const isViewMode = accountType === 'view';
  const fullClassName = buildClassName(
    className,
    styles.account,
    imageUrl && styles.customCard,
    imageUrl && mtwCardClassNames,
    isActive && !withCheckbox && styles.account_current,
    isLoading && styles.account_disabled,
    !onClick && styles.account_inactive,
  );

  return (
    <div
      key={accountId}
      className={fullClassName}
      onClick={onClick}
      style={buildStyle(imageUrl && `--bg: url(${imageUrl})`)}
      aria-label={ariaLabel}
    >
      {title && (
        <span className={buildClassName(styles.accountName, titleClassName, withTextGradient && 'gradientText')}>
          {title}
        </span>
      )}
      <div className={buildClassName(styles.accountFooter, withTextGradient && 'gradientText')}>
        {isViewMode && <i className={buildClassName('icon-eye-filled', styles.icon)} aria-hidden />}
        {isHardware && <i className={buildClassName('icon-ledger', styles.icon)} aria-hidden />}
        <span className={styles.accountAddress}>
          {shortenAddress(
            address,
            isHardware ? ACCOUNT_WITH_ICON_ADDRESS_SHIFT : ACCOUNT_ADDRESS_SHIFT,
            ACCOUNT_ADDRESS_SHIFT,
          )}
        </span>
      </div>
      {withCheckbox
        && <div className={buildClassName(styles.accountCheckMark, isActive && styles.accountCheckMark_active)} />}
    </div>
  );
}

export default memo(AccountButton);
