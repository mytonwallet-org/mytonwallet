import React, { memo } from '../../../../lib/teact/teact';

import useLang from '../../../../hooks/useLang';
import useShowTransition from '../../../../hooks/useShowTransition';

import styles from './AccountSelectorModal.module.scss';

type OwnProps = {
  isVisible?: boolean;
  onClick: NoneToVoidFunction;
};

const WalletVersionSection = ({ isVisible, onClick }: OwnProps) => {
  const lang = useLang();
  const {
    shouldRender,
    ref,
  } = useShowTransition({ isOpen: isVisible, withShouldRender: true });

  if (!shouldRender) return undefined;

  return (
    <div ref={ref} className={styles.walletVersionBlock}>
      <span>
        {lang('$wallet_switch_version_1', {
          action: (
            <div
              role="button"
              tabIndex={0}
              className={styles.walletVersionText}
              onClick={onClick}
            >
              {lang('$wallet_switch_version_2')}
            </div>
          ),
        })}
      </span>
    </div>
  );
};

export default memo(WalletVersionSection);
