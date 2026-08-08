import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { Account, GlobalState } from '../../global/types';

import { TONCOIN } from '../../config';
import {
  selectAccountStakingState,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectHasMultipleAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getIsActiveStakingState } from '../../util/staking';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import Modal from '../ui/Modal';
import StakingInfoContent from './StakingInfoContent';

import styles from './Staking.module.scss';

interface OwnProps {
  isOpen?: boolean;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  tokenSlug?: string;
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
  byAccountId?: GlobalState['byAccountId'];
}

function StakingInfoModal({
  isOpen,
  tokenSlug,
  accountId,
  accountTitle,
  hasMultipleAccounts,
  byAccountId,
  onClose,
}: OwnProps & StateProps) {
  const { fetchStakingHistory, switchAccount } = getActions();

  const [isSelectorOpen, openSelector, closeSelector] = useFlag();

  const withBackground = tokenSlug !== TONCOIN.slug;

  useEffect(() => {
    if (isOpen) {
      fetchStakingHistory();
    }
  }, [fetchStakingHistory, isOpen, accountId]);

  useEffect(() => {
    if (!isOpen) {
      closeSelector();
    }
  }, [isOpen, closeSelector]);

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    switchAccount({ accountId: nextAccountId });
    closeSelector();
  });

  const getIsAccountDisabled = useLastCallback((_: Account, targetAccountId: string) => {
    const stateById = byAccountId?.[targetAccountId]?.staking?.stateById;
    return !stateById || !Object.values(stateById).some(getIsActiveStakingState);
  });

  return (
    <>
      <Modal
        isOpen={isOpen}
        dialogClassName={buildClassName(styles.stakingInfoModalDialog, isSelectorOpen && styles.dialogBehindSelector)}
        contentClassName={buildClassName(styles.stakingInfoModalContent, withBackground && styles.withBackground)}
        onClose={onClose}
      >
        <StakingInfoContent isActive={isOpen} onClose={onClose} />
        {hasMultipleAccounts && accountId && (
          <AccountSwitcherPill
            accountId={accountId}
            title={accountTitle}
            className={buildClassName(styles.accountPill, styles.accountPillPurple)}
            onClick={openSelector}
          />
        )}
      </Modal>

      <Modal
        isOpen={Boolean(isOpen) && isSelectorOpen}
        dialogClassName={styles.modalDialog}
        noBackdrop
        onClose={closeSelector}
      >
        <AccountSwitcherSlide
          isActive={isSelectorOpen}
          getIsAccountDisabled={getIsAccountDisabled}
          onAccountSelect={handleSelectAccount}
          onBack={closeSelector}
          onClose={onClose}
        />
      </Modal>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;

  return {
    tokenSlug: stakingState?.tokenSlug,
    accountId,
    accountTitle: selectCurrentAccount(global)?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
    byAccountId: global.byAccountId,
  };
})(StakingInfoModal));
