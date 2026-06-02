import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import useHistoryBack from '../../hooks/useHistoryBack';
import useInterval from '../../hooks/useInterval';

import MfaConfirm from '../common/MfaConfirm';
import ModalHeader from '../ui/ModalHeader';

interface OwnProps {
  isActive?: boolean;
  onClose: () => void;
  children?: TeactNode;
}

interface StateProps {
  currentSwap: {
    mfaRequestHash?: string;
  };
}

function SwapMfaConfirm({
  isActive,
  onClose,
  currentSwap: { mfaRequestHash },
  children,
}: OwnProps & StateProps) {
  const { updateSwapMfaRequestStatus } = getActions();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  useInterval(() => {
    if (isActive && mfaRequestHash) updateSwapMfaRequestStatus();
  }, 1000);

  return (
    <>
      <ModalHeader onClose={onClose} />
      <MfaConfirm onClose={onClose} mfaRequestHash={mfaRequestHash}>
        {children}
      </MfaConfirm>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    currentSwap: {
      mfaRequestHash: global.currentSwap.mfaRequestHash,
    },
  };
})(SwapMfaConfirm));
