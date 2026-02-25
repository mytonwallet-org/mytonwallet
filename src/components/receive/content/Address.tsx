import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiChain } from '../../../api/types';

import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';

import useLang from '../../../hooks/useLang';
import useQrCode from '../../../hooks/useQrCode';

import InteractiveTextField from '../../ui/InteractiveTextField';
import Actions from './Actions';

import styles from '../ReceiveModal.module.scss';

interface OwnProps {
  chain: ApiChain;
  isActive?: boolean;
  isStatic?: boolean;
  isLedger?: boolean;
  address: string;
  onClose?: NoneToVoidFunction;
}

function Address({
  chain,
  isActive,
  isStatic,
  isLedger,
  address,
  onClose,
}: OwnProps) {
  const { verifyHardwareAddress } = getActions();

  const lang = useLang();
  const { qrCodeRef, isInitialized } = useQrCode({
    address,
    chain,
    isActive,
    hiddenClassName: styles.qrCodeHidden,
    preferUrl: true,
  });
  const qrClassNames = buildClassName(
    styles.qrCode,
    isStatic && styles.qrCodeStatic,
    !isInitialized && styles.qrCodeHidden,
  );

  const handleVerify = (e: React.MouseEvent<HTMLAnchorElement>) => {
    e.preventDefault();
    e.stopPropagation();

    verifyHardwareAddress({ chain });
  };

  return (
    <div>
      <div className={buildClassName(styles.contentTitle, styles.contentTitleQr)}>
        {renderText(lang('$receive_description'))}
      </div>

      <div className={qrClassNames} ref={qrCodeRef} />

      <InteractiveTextField
        chain={chain}
        address={address}
        className={isStatic ? styles.copyButtonStatic : styles.addressWrapper}
        copyNotification={lang('%chain% Address Copied', { chain: getChainTitle(chain) }) as string}
        noSavedAddress
        noDimming
      />

      {isLedger && (
        <div
          className={buildClassName(
            styles.contentTitle, styles.contentTitleLedger, isStatic && styles.contentTitleLedgerStatic,
          )}
        >
          {renderText(lang('$ledger_verify_address'))}
          {' '}
          <a href="#" onClick={handleVerify} className={styles.dottedLink}>
            {lang('Verify now')}
          </a>
        </div>
      )}

      {!isStatic && <Actions chain={chain} isLedger={isLedger} onClose={onClose} />}
    </div>
  );
}

export default memo(Address);
