import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { TONCOIN } from '../../config';
import { selectAccountStakingHistory, selectAccountStakingState, selectCurrentAccountId } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';

import Modal from '../ui/Modal';
import StakingInfoContent from './StakingInfoContent';

import styles from './Staking.module.scss';

interface OwnProps {
  isOpen?: boolean;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  tokenSlug?: string;
  hasHistory?: boolean;
}

function StakingInfoModal({
  isOpen,
  tokenSlug,
  hasHistory,
  onClose,
}: OwnProps & StateProps) {
  const { fetchStakingHistory } = getActions();
  const withBackground = tokenSlug !== TONCOIN.slug;

  useEffect(() => {
    if (isOpen) {
      fetchStakingHistory();
    }
  }, [fetchStakingHistory, isOpen]);

  return (
    <Modal
      isOpen={isOpen}
      contentClassName={buildClassName(styles.stakingInfoModalContent, withBackground && styles.withBackground)}
      onClose={onClose}
    >
      <StakingInfoContent isActive={isOpen} onClose={onClose} />
    </Modal>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = selectCurrentAccountId(global);
  const stakingHistory = accountId
    ? selectAccountStakingHistory(global, accountId)
    : undefined;
  const stakingState = accountId ? selectAccountStakingState(global, accountId) : undefined;

  return {
    tokenSlug: stakingState?.tokenSlug,
    hasHistory: Boolean(stakingHistory?.length),
  };
})(StakingInfoModal));
