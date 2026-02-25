import React, { memo } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { ApiChain } from '../../../api/types';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './DeleteSavedAddressModal.module.scss';

interface OwnProps {
  isOpen?: boolean;
  address?: string;
  chain?: ApiChain;
  onClose: NoneToVoidFunction;
}

function DeleteSavedAddressModal({
  isOpen, address, chain, onClose,
}: OwnProps) {
  const { removeFromSavedAddress, showToast } = getActions();

  const lang = useLang();

  const handleDeleteSavedAddress = useLastCallback(() => {
    removeFromSavedAddress({ address: address!, chain: chain! });
    showToast({ message: lang('Address removed from saved'), icon: 'icon-trash' });
    onClose();
  });

  return (
    <Modal
      title={lang('Delete Saved Address')}
      isCompact
      isOpen={isOpen}
      onClose={onClose}
    >
      <p className={styles.text}>{lang('Are you sure you want to remove this address from your saved ones?')}</p>

      <p className={styles.text}>{lang('You will be able to save it again via Transfer Info with this address.')}</p>

      <div className={modalStyles.buttons}>
        <Button onClick={onClose} className={modalStyles.button}>{lang('Cancel')}</Button>
        <Button isDestructive onClick={handleDeleteSavedAddress} className={modalStyles.button}>
          {lang('Delete')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(DeleteSavedAddressModal);
