import React, { memo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import { getHelpCenterUrl } from '../../../../global/helpers/getHelpCenterUrl';
import { selectCurrentAccount, selectCurrentAccountSettings } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';

import Collapsible from '../../../ui/Collapsible';

import styles from './Warnings.module.scss';

type StateProps = {
  isMultisig?: boolean;
  isViewMode?: boolean;
  isHidden?: boolean;
};

function TronScamWarning({ isMultisig, isViewMode, isHidden }: StateProps) {
  const { closeTronScamWarning } = getActions();

  const { isLandscape } = useDeviceScreen();
  const lang = useLang();

  const isShown = Boolean(isMultisig && !isViewMode && !isHidden);

  function handleClose(e: React.MouseEvent<HTMLButtonElement>) {
    e.stopPropagation();
    closeTronScamWarning();
  }

  const helpCenterLink = getHelpCenterUrl(lang.code, 'seedScam');

  return (
    <Collapsible isShown={isShown}>
      <div className={buildClassName(styles.wrapper, isLandscape && styles.wrapper_landscape)}>
        {lang('Multisig Wallet Detected')}
        <p className={styles.text}>
          {lang('$multisig_warning_text', {
            multisig_warning_link: (
              <span className={styles.linkContainer}>
                <i className={buildClassName(styles.link, 'icon-chevron-right')} aria-hidden />
                <a href={helpCenterLink} className={styles.link} target="_blank" rel="noreferrer">
                  {lang('$multisig_warning_link')}
                </a>
              </span>
            ),
          })}
        </p>

        <button type="button" className={styles.closeButton} aria-label={lang('Close')} onClick={handleClose}>
          <i className="icon-close" aria-hidden />
        </button>
      </div>
    </Collapsible>
  );
}

export default memo(withGlobal((global): StateProps => {
  const account = selectCurrentAccount(global);
  const accountSettings = selectCurrentAccountSettings(global);

  return {
    isMultisig: account?.isMultisigByChain?.tron,
    isViewMode: account?.type === 'view',
    isHidden: accountSettings?.isTronScamWarningHidden,
  };
})(TronScamWarning));
