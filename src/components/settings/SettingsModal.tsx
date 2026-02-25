import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import { IS_EXTENSION } from '../../config';
import buildClassName from '../../util/buildClassName';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import Modal from '../ui/Modal';

import styles from './Settings.module.scss';

interface OwnProps {
  children: TeactNode;
  isOpen?: boolean;
  onClose: () => void;
}

interface StateProps {
  isMediaViewerOpen?: boolean;
}

function SettingsModal({
  children, isOpen, onClose, isMediaViewerOpen,
}: OwnProps & StateProps) {
  const fullDialogClassName = buildClassName(
    styles.modalDialog,
    !(IS_ELECTRON || IS_EXTENSION) && styles.modalDialogWeb,
  );

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen && !isMediaViewerOpen}
      dialogClassName={fullDialogClassName}
      contentClassName={styles.modalContent}
      onClose={onClose}
    >
      {children}
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isMediaViewerOpen: Boolean(global.mediaViewer.mediaId),
  };
})(SettingsModal));
