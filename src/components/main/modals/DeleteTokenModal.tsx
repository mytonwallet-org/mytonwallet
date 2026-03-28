import React, {
  memo, useState,
} from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { UserToken } from '../../../global/types';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './DeleteTokenModal.module.scss';

interface OwnProps {
  token?: UserToken;
  onClose?: NoneToVoidFunction;
}

function DeleteTokenModal({ token, onClose }: OwnProps) {
  const {
    deleteToken,
  } = getActions();

  const [isOpen, setIsOpen] = useState(false);
  const lang = useLang();

  useSyncEffect(() => {
    if (token) {
      setIsOpen(true);
    }
  }, [token]);

  const handleClose = useLastCallback(() => {
    setIsOpen(false);
    onClose?.();
  });

  const handleDeleteToken = useLastCallback(() => {
    handleClose();
    deleteToken({ slug: token!.slug });
  });

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      onClose={handleClose}
      title={lang('Delete Token')}
      contentClassName={styles.content}
    >
      <p className={styles.description}>
        {lang('Are you sure you want to delete?', { token: <strong>{token?.name}</strong> })}
      </p>
      <div className={modalStyles.buttons}>
        <Button onClick={handleClose} className={modalStyles.button}>{lang('Cancel')}</Button>
        <Button isDestructive onClick={handleDeleteToken} className={modalStyles.button}>
          {lang('Delete')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(DeleteTokenModal);
