import React, {
  memo, useEffect, useMemo, useState,
} from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { Account, AccountState } from '../../../global/types';

import { IS_CORE_WALLET } from '../../../config';
import renderText from '../../../global/helpers/renderText';
import {
  selectCurrentAccountId,
  selectNetworkAccounts,
  selectOrderedAccounts,
} from '../../../global/selectors';
import { getAccountTitle } from '../../../util/account';
import buildClassName from '../../../util/buildClassName';
import isViewAccount from '../../../util/isViewAccount';
import { IS_IOS_APP } from '../../../util/windowEnvironment';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Checkbox from '../../ui/Checkbox';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './LogOutModal.module.scss';

interface OwnProps {
  isOpen?: boolean;
  onClose: (shouldCloseSettings: boolean) => void;
  isInAppLock?: boolean;
  // If provided, logout will be performed for this account instead of current
  targetAccountId?: string;
}

interface StateProps {
  accountId: string;
  hasManyAccounts: boolean;
  accounts: Record<string, Account>;
  orderedAccounts: Array<[string, Account]>;
  accountStates: Record<string, AccountState>;
  isBackupRequired?: boolean;
  isViewMode: boolean;
}

interface LinkAccount {
  id: string;
  title: string;
}

function LogOutModal({
  isOpen,
  accountId,
  hasManyAccounts,
  orderedAccounts,
  accountStates,
  isBackupRequired,
  isViewMode,
  isInAppLock,
  onClose,
}: OwnProps & StateProps) {
  const { signOut, switchAccount } = getActions();

  const lang = useLang();
  const [isLogOutFromAllAccounts, setIsLogOutFromAllAccounts] = useState<boolean>(IS_CORE_WALLET || !!isInAppLock);

  const accountsWithoutBackups = useMemo(() => {
    if (!hasManyAccounts) {
      return [];
    }

    return orderedAccounts.reduce<LinkAccount[]>((acc, [id, account]) => {
      if (id !== accountId && accountStates[id]?.isBackupRequired) {
        acc.push({
          id,
          title: getAccountTitle(account) ?? '',
        });
      }

      return acc;
    }, []);
  }, [orderedAccounts, accountStates, accountId, hasManyAccounts]);

  useEffect(() => {
    if (isOpen) {
      setIsLogOutFromAllAccounts(IS_CORE_WALLET || !!isInAppLock);
    }
  }, [isOpen, isInAppLock]);

  const handleSwitchAccount = (accountId: string) => {
    onClose(false);
    switchAccount({ accountId });
  };

  const handleLogOut = useLastCallback(() => {
    onClose(!isLogOutFromAllAccounts && hasManyAccounts);
    const level = IS_CORE_WALLET ? 'all' : (isLogOutFromAllAccounts ? 'network' : 'account');
    signOut({ level, accountId: level === 'account' ? accountId : undefined });
  });

  const handleClose = useLastCallback(() => {
    onClose(false);
  });

  function renderAccountLink(account: LinkAccount, idx: number) {
    const { id, title } = account;

    const fullClassName = buildClassName(
      !isInAppLock && styles.accountLink,
      idx + 2 === accountsWithoutBackups.length && styles.penultimate,
    );

    if (isInAppLock) {
      return (
        <span className={fullClassName}>
          <strong>{title}</strong>
        </span>
      );
    }

    return (
      <span className={fullClassName}>
        <a
          key={id}
          href="#"
          className={styles.accountLink_inner}
          onClick={(e: React.MouseEvent) => {
            e.preventDefault();
            handleSwitchAccount(id);
          }}
        >
          {title}
        </a>
      </span>
    );
  }

  function renderBackupWarning() {
    return (
      <p className={modalStyles.text}>
        <b className={styles.warning}>{lang('Warning!')}</b> {lang('$logout_without_backup_warning')}
      </p>
    );
  }

  function renderBackupForAccountsWarning() {
    return (
      <p className={modalStyles.text}>
        <b className={styles.warning}>{lang('Warning!')}</b>{' '}
        {lang('$logout_accounts_without_backup_warning', {
          links: <>{accountsWithoutBackups.map(renderAccountLink)}</>,
        })}
      </p>
    );
  }

  const shouldRenderWarningForAnotherAccounts = isLogOutFromAllAccounts && accountsWithoutBackups.length > 0;
  const shouldRenderWarningForCurrentAccount = isBackupRequired && !shouldRenderWarningForAnotherAccounts;
  // Sibling button has wider text on iOS due to App Store "Remove Wallet" requirements
  const cancelButtonClassNames = buildClassName(modalStyles.button, IS_IOS_APP && modalStyles.shortButton);

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={lang('Remove')}
      onClose={handleClose}
      isInAppLock={isInAppLock}
    >
      <p className={buildClassName(modalStyles.text, modalStyles.text_noExtraMargin)}>
        {renderText(isViewMode ? lang('$logout_view_mode_warning') : lang('$logout_warning', '12/24'))}
      </p>
      {!(IS_CORE_WALLET || !!isInAppLock) && hasManyAccounts && (
        <Checkbox
          id="logount_all_accounts"
          className={styles.checkbox}
          checked={isLogOutFromAllAccounts}
          onChange={setIsLogOutFromAllAccounts}
        >
          {renderText(lang('$logout_confirm'))}
        </Checkbox>
      )}

      {shouldRenderWarningForCurrentAccount && renderBackupWarning()}
      {shouldRenderWarningForAnotherAccounts && renderBackupForAccountsWarning()}

      <div className={modalStyles.buttons}>
        <Button className={cancelButtonClassNames} onClick={handleClose}>
          {lang('Cancel')}
        </Button>
        <Button isDestructive onClick={handleLogOut} className={modalStyles.button}>
          {IS_IOS_APP ? lang('Remove Wallet') : lang('Exit')}
        </Button>
      </div>
    </Modal>
  );
}

export default memo(
  withGlobal<OwnProps>((global, ownProps): StateProps => {
    const accounts = selectNetworkAccounts(global) || {};
    const orderedAccounts = selectOrderedAccounts(global);
    const fallbackAccountId = selectCurrentAccountId(global);
    const accountId = ownProps.targetAccountId ?? fallbackAccountId!;
    const targetAccountState = global.byAccountId[accountId];
    const accountIds = Object.keys(accounts);
    const hasManyAccounts = accountIds.length > 1;
    const targetAccount = accounts[accountId];
    const isViewMode = targetAccount && isViewAccount(targetAccount.type);

    return {
      accountId,
      hasManyAccounts,
      accounts,
      orderedAccounts,
      accountStates: global.byAccountId,
      isBackupRequired: targetAccountState?.isBackupRequired,
      isViewMode,
    };
  })(LogOutModal),
);
