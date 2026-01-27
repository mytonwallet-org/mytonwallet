import React, { memo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import { IS_EXPLORER } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { getIsMobileTelegramApp, IS_IOS } from '../../../../util/windowEnvironment';

import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useQrScannerSupport from '../../../../hooks/useQrScannerSupport';

import Button from '../../../ui/Button';

import styles from './actionButtons/Buttons.module.scss';

interface OwnProps {
  isViewMode?: boolean;
}

function QrScannerButton({ isViewMode }: OwnProps) {
  const { requestOpenQrScanner } = getActions();

  const lang = useLang();
  const isQrScannerSupported = useQrScannerSupport() && !isViewMode && !IS_EXPLORER;

  const handleQrScanClick = useLastCallback(() => {
    if (IS_IOS && getIsMobileTelegramApp()) {
      alert('Scanning is temporarily not available');
      return;
    }

    requestOpenQrScanner();
  });

  if (!isQrScannerSupported) return undefined;

  return (
    <Button
      className={buildClassName(styles.button, styles.qrScannerButton)}
      isText
      isSimple
      kind="transparent"
      ariaLabel={lang('Scan QR Code')}
      onClick={handleQrScanClick}
    >
      <i className="icon-qr-scanner" aria-hidden />
    </Button>
  );
}

export default memo(QrScannerButton);
