import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { getHelpCenterUrl } from '../../../../global/helpers/getHelpCenterUrl';
import { selectIsCurrentAccountViewMode, selectIsMultisigAccount } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';

import Collapsible from '../../../ui/Collapsible';

import styles from './Warnings.module.scss';

type StateProps = {
  isMultisig: boolean;
  isViewMode: boolean;
};

function ScamWalletWarning({ isMultisig, isViewMode }: StateProps) {
  const { isLandscape } = useDeviceScreen();
  const lang = useLang();

  const isShown = isMultisig && !isViewMode;

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
      </div>
    </Collapsible>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isMultisig: !!global.currentAccountId && selectIsMultisigAccount(global, global.currentAccountId),
    isViewMode: selectIsCurrentAccountViewMode(global),
  };
})(ScamWalletWarning));
