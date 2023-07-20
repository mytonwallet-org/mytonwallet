import React, { memo, useEffect } from '../../lib/teact/teact';

import { getActions, withGlobal } from '../../global';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';

import useForceUpdate from '../../hooks/useForceUpdate';
import useInterval from '../../hooks/useInterval';

import Modal from '../ui/Modal';
import StakingInfoContent from './StakingInfoContent';

import styles from './Staking.module.scss';

interface OwnProps {
  isOpen?: boolean;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  isUnstakeRequested?: boolean;
}

const UPDATE_UNSTAKE_DATE_INTERVAL_MS = 30000; // 30 sec

function StakingInfoModal({
  isOpen,
  isUnstakeRequested,
  onClose,
}: OwnProps & StateProps) {
  const { fetchBackendStakingState } = getActions();

  const forceUpdate = useForceUpdate();

  useInterval(forceUpdate, isUnstakeRequested ? UPDATE_UNSTAKE_DATE_INTERVAL_MS : undefined);

  useEffect(() => {
    if (isOpen) {
      fetchBackendStakingState();
    }
  }, [fetchBackendStakingState, isOpen]);

  return (
    <Modal
      isOpen={isOpen}
      isSlideUp
      onClose={onClose}
      contentClassName={buildClassName(styles.stakingInfoModalContent)}
    >
      <StakingInfoContent isActive={isOpen} onClose={onClose} />
    </Modal>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountState = selectCurrentAccountState(global);

  return {
    isUnstakeRequested: accountState?.isUnstakeRequested,
  };
})(StakingInfoModal));
