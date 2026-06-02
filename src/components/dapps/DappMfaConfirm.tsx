import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import useHistoryBack from '../../hooks/useHistoryBack';
import useInterval from '../../hooks/useInterval';

import MfaConfirm from '../common/MfaConfirm';
import ModalHeader from '../ui/ModalHeader';

interface OwnProps {
  isActive?: boolean;
  error?: string;
  onClose: () => void;
}

interface StateProps {
  currentDappTransfer: {
    mfaRequestHash?: string;
  };
}

function DappMfaConfirm({
  isActive,
  onClose,
  currentDappTransfer: { mfaRequestHash },
}: OwnProps & StateProps) {
  const { updateDappMfaRequestStatus } = getActions();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  useInterval(() => {
    if (isActive && mfaRequestHash) updateDappMfaRequestStatus();
  }, 1000);

  return (
    <>
      <ModalHeader onClose={onClose} />
      <MfaConfirm
        onClose={onClose}
        mfaRequestHash={mfaRequestHash}
      />
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { mfaRequestHash } = global.currentDappTransfer;

  return {
    currentDappTransfer: {
      mfaRequestHash,
    },
  };
})(DappMfaConfirm));
