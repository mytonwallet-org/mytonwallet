import React, { memo } from '../../../../lib/teact/teact';

import { APP_INSTALL_URL, NEW_APP_URL, PRODUCTION_URL } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useForceUpdate from '../../../../hooks/useForceUpdate';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';

import Button from '../../../ui/Button';

import styles from './Warnings.module.scss';

type OwnProps = {
  isMnemonicAccount: boolean;
  onOpenBackupWallet: () => void;
};

const NEW_DOMAIN = new URL(PRODUCTION_URL).hostname;

// Module scope on purpose: `Main` is remounted on every account switch (see `mainKey` in App.tsx), so component
// state would resurrect the banner. Dying with the page is the intended lifetime - a reload shows it again.
let isDismissed = false;

function LegacyDomainWarning({ isMnemonicAccount, onOpenBackupWallet }: OwnProps) {
  const { shouldRender, ref } = useShowTransition({
    isOpen: !isDismissed,
    noMountTransition: true,
    withShouldRender: true,
  });
  const { isLandscape } = useDeviceScreen();
  const forceUpdate = useForceUpdate();

  const lang = useLang();

  const handleClose = useLastCallback(() => {
    isDismissed = true;

    forceUpdate();
  });

  if (!shouldRender) {
    return undefined;
  }

  return (
    <div
      ref={ref}
      className={buildClassName(styles.wrapper, styles.wrapperStatic, isLandscape && styles.wrapper_landscape)}
    >
      {lang('Deprecated Website')}
      <p className={styles.text}>
        {lang('This version is deprecated. Re-import your wallets on %new_domain% or %download_app%.', {
          new_domain: (
            <a href={NEW_APP_URL} target="_blank" rel="noopener noreferrer" className={styles.textLink}>
              {NEW_DOMAIN}
            </a>
          ),
          download_app: (
            <a href={APP_INSTALL_URL} target="_blank" rel="noopener noreferrer" className={styles.textLink}>
              {lang('download the app')}
            </a>
          ),
        })}
      </p>

      {isMnemonicAccount && (
        <div className={styles.actions}>
          <Button isSmall className={styles.actionButton} onClick={onOpenBackupWallet}>
            {lang('Back Up Secret Words')}
          </Button>
        </div>
      )}

      <button type="button" className={styles.closeButton} aria-label={lang('Close')} onClick={handleClose}>
        <i className="icon-close" aria-hidden />
      </button>
    </div>
  );
}

export default memo(LegacyDomainWarning);
