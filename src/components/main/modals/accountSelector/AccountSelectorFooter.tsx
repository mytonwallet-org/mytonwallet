import React, { memo } from '../../../../lib/teact/teact';

import { AccountSelectorState } from '../../../../global/types';

import buildClassName from '../../../../util/buildClassName';
import { AccountTab } from './constants';

import useLang from '../../../../hooks/useLang';
import { useTransitionActiveKey } from '../../../../hooks/useTransitionActiveKey';

import Button from '../../../ui/Button';
import Transition from '../../../ui/Transition';

import styles from './AccountSelectorModal.module.scss';

interface OwnProps {
  tab: AccountTab;
  renderingState: AccountSelectorState;
  withBorder: boolean;
  onAddWallet: NoneToVoidFunction;
  onReorderDone: NoneToVoidFunction;
}

function AccountSelectorFooter({
  tab,
  renderingState,
  withBorder,
  onAddWallet,
  onReorderDone,
}: OwnProps) {
  const lang = useLang();
  const isReorderMode = renderingState === AccountSelectorState.Reorder;
  const title = tab === AccountTab.Ledger
    ? 'Add Ledger Wallet'
    : (tab === AccountTab.View ? 'Add View Wallet' : 'Add New Wallet');
  const activeKey = useTransitionActiveKey([isReorderMode, title]);

  return (
    <div className={buildClassName(styles.footer, withBorder && styles.withBorder)}>
      <Transition
        activeKey={activeKey}
        name="semiFade"
      >
        {isReorderMode ? (
          <Button isPrimary className={styles.footerButton} onClick={onReorderDone}>
            {lang('Done')}
          </Button>
        ) : (
          <Button isPrimary className={styles.footerButton} onClick={onAddWallet}>
            <i className={buildClassName(styles.plusIcon, 'icon-plus')} aria-hidden />
            {lang(title)}
          </Button>
        )}
      </Transition>
    </div>
  );
}

export default memo(AccountSelectorFooter);
