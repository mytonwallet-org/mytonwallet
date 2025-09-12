import React from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';
import type { Account, AccountType } from '../../../../global/types';

import { getMainAccountAddress } from '../../../../util/account';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { stopEvent } from '../../../../util/domEvents';
import { isKeyCountGreater } from '../../../../util/isEmptyObject';
import { shortenAddress } from '../../../../util/shortenAddress';

import { useCachedImage } from '../../../../hooks/useCachedImage';
import useCardCustomization from '../../../../hooks/useCardCustomization';
import useLang from '../../../../hooks/useLang';

import styles from './AccountButton.module.scss';

interface OwnProps {
  isActive: boolean;
  accountId: string;
  byChain: Account['byChain'];
  accountType: AccountType;
  title?: string;
  cardBackgroundNft?: ApiNft;
  canEditAccount?: boolean;
  onClick: (accountId: string) => void;
  onEdit: NoneToVoidFunction;
}

export const ACCOUNT_WITH_ICON_ADDRESS_SHIFT = 3;
export const ACCOUNT_ADDRESS_SHIFT = 4;

function AccountButton({
  isActive,
  accountId,
  byChain,
  accountType,
  title,
  cardBackgroundNft,
  canEditAccount,
  onClick,
  onEdit,
}: OwnProps) {
  const lang = useLang();

  const isHardware = accountType === 'hardware';
  const isViewMode = accountType === 'view';

  const addressOrMultichain = isKeyCountGreater(byChain, 1)
    ? lang('Multichain')
    : shortenAddress(
      getMainAccountAddress(byChain) ?? '',
      accountType !== 'mnemonic' ? ACCOUNT_WITH_ICON_ADDRESS_SHIFT : ACCOUNT_ADDRESS_SHIFT,
      ACCOUNT_ADDRESS_SHIFT,
    );

  const {
    backgroundImageUrl,
    withTextGradient,
    classNames: mtwCardClassNames,
  } = useCardCustomization(cardBackgroundNft);
  const { imageUrl } = useCachedImage(backgroundImageUrl);
  const fullClassName = buildClassName(
    styles.button,
    isActive && styles.current,
    imageUrl && styles.customCard,
    imageUrl && mtwCardClassNames,
  );

  const handleEditClick = (e: React.MouseEvent) => {
    stopEvent(e);

    onEdit();
  };

  return (
    <div
      className={fullClassName}
      aria-label={lang('Switch Account')}
      onClick={isActive ? undefined : () => onClick(accountId)}
      style={buildStyle(imageUrl && `--bg: url(${imageUrl})`)}
    >
      {title && <span className={buildClassName(styles.accountName, withTextGradient && 'gradientText')}>{title}</span>}
      <div className={buildClassName(styles.accountAddressBlock, withTextGradient && 'gradientText')}>
        {isHardware && <i className="icon-ledger" aria-hidden />}
        {isViewMode && <i className="icon-eye-filled" aria-hidden />}
        <span>{addressOrMultichain}</span>
      </div>

      {isActive && canEditAccount && (
        <div className={styles.edit} onClick={handleEditClick}>
          <i className="icon-pen" aria-hidden />
        </div>
      )}
    </div>
  );
}

export default AccountButton;
