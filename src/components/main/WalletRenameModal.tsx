import React, {
  memo, useEffect, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import { selectAccount } from '../../global/selectors';
import { stopEvent } from '../../util/domEvents';

import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Input from '../ui/Input';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';

interface StateProps {
  accountId?: string;
  accountTitle?: string;
}

const ACCOUNT_NAME_MAX_LENGTH = 255;

function WalletRenameModal({ accountId, accountTitle }: StateProps) {
  const { renameAccount, closeWalletRenameModal } = getActions();

  const lang = useLang();
  const inputRef = useRef<HTMLInputElement>();
  const [newName, setNewName] = useState<string>(accountTitle ?? '');
  const isOpen = Boolean(accountId);

  useEffect(() => {
    if (isOpen && accountTitle !== undefined) {
      setNewName(accountTitle);
    }
  }, [isOpen, accountTitle]);

  useFocusAfterAnimation(inputRef, !isOpen);

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);

    if (newName.trim().length === 0 || !accountId) return;

    renameAccount({ accountId, title: newName.trim() });
    closeWalletRenameModal();
  });

  return (
    <Modal
      isCompact
      isOpen={isOpen}
      title={lang('Rename Wallet')}
      onClose={closeWalletRenameModal}
    >
      <form action="#" onSubmit={handleSubmit}>
        <p>{lang('You can rename this wallet for easier identification.')}</p>
        <Input
          ref={inputRef}
          placeholder={lang('Name')}
          onInput={setNewName}
          value={newName}
          maxLength={ACCOUNT_NAME_MAX_LENGTH}
          enterKeyHint="done"
        />

        <div className={modalStyles.buttons}>
          <Button onClick={closeWalletRenameModal} className={modalStyles.button}>{lang('Cancel')}</Button>
          <Button
            isPrimary
            isSubmit
            isDisabled={newName.trim().length === 0}
            className={modalStyles.button}
          >
            {lang('Save')}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountId = global.walletRenameAccountId;

  return {
    accountId,
    accountTitle: accountId ? selectAccount(global, accountId)?.title : undefined,
  };
})(WalletRenameModal));
