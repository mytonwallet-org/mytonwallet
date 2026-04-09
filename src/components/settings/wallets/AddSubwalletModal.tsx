import React, { memo, useState } from '../../../lib/teact/teact';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Checkbox from '../../ui/Checkbox';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from '../Settings.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
  onAdd: (shouldReplace: boolean) => void;
}

function AddSubwalletModal({ isOpen, onClose, onAdd }: OwnProps) {
  const lang = useLang();
  const [shouldReplace, setShouldReplace] = useState(true);

  const handleAdd = useLastCallback(() => {
    onAdd(shouldReplace);
    setShouldReplace(true);
  });

  const handleClose = useLastCallback(() => {
    onClose();
    setShouldReplace(true);
  });

  return (
    <Modal
      isCompact
      isOpen={isOpen}
      title={lang('Add Subwallet')}
      onClose={handleClose}
    >
      <Checkbox
        checked={shouldReplace}
        className={styles.checkbox}
        onChange={setShouldReplace}
      >
        {lang('Replace in this wallet')}
      </Checkbox>

      <div className={modalStyles.buttons}>
        <Button onClick={handleClose} className={modalStyles.button}>{lang('Cancel')}</Button>
        <Button
          isPrimary
          onClick={handleAdd}
          className={modalStyles.button}
        >
          {lang('Add')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(AddSubwalletModal);
