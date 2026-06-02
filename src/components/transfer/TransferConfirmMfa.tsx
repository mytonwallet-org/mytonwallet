import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { type GlobalState } from '../../global/types';

import useHistoryBack from '../../hooks/useHistoryBack';
import useInterval from '../../hooks/useInterval';

import MfaConfirm from '../common/MfaConfirm';
import ModalHeader from '../ui/ModalHeader';

interface OwnProps {
  isActive?: boolean;
  error?: string;
  onClose: () => void;
  children: TeactNode;
}

interface StateProps {
  currentTransfer: GlobalState['currentTransfer'];
}

function TransferConfirmMfa({
  isActive,
  onClose,
  currentTransfer: { mfaRequestHash },
  children,
}: OwnProps & StateProps) {
  const { updateMfaRequestStatus } = getActions();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  useInterval(() => {
    if (isActive && mfaRequestHash) updateMfaRequestStatus();
  }, 1000);

  return (
    <>
      <ModalHeader onClose={onClose} />
      <MfaConfirm
        onClose={onClose}
        mfaRequestHash={mfaRequestHash}
      >
        {children}
      </MfaConfirm>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    currentTransfer: global.currentTransfer,
  };
})(TransferConfirmMfa));
