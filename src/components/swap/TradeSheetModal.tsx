import type { TeactNode } from '../../lib/teact/teact';
import React from '../../lib/teact/teact';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';

import Modal from '../ui/Modal';

import styles from './TradeSheetModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  title: string;
  children: TeactNode;
  onClose: NoneToVoidFunction;
}

/** A sheet over the trade sheet in portrait, and a compact modal in landscape */
function TradeSheetModal({
  isOpen, title, children, onClose,
}: OwnProps) {
  const { isPortrait } = useDeviceScreen();

  return (
    <Modal
      isOpen={isOpen}
      isCompact={!isPortrait}
      noBackdrop={isPortrait}
      className={isPortrait ? styles.sheet : undefined}
      dialogClassName={styles.dialog}
      title={title}
      hasCloseButton
      onClose={onClose}
    >
      {children}
    </Modal>
  );
}

export default TradeSheetModal;
