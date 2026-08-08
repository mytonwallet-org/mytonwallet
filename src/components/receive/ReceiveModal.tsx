import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectDefaultOnRampChain,
  selectHasMultipleAccounts,
  selectIsHardwareAccount,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useAccountSwitcherScreen, { AccountSwitcherScreen } from '../../hooks/useAccountSwitcherScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';
import Content from './Content';

import modalStyles from '../ui/Modal.module.scss';
import styles from './ReceiveModal.module.scss';

type StateProps = {
  isOpen?: boolean;
  isLedger?: boolean;
  isTestnet?: boolean;
  isSwapDisabled: boolean;
  isOnRampDisabled: boolean;
  currentAccountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
};

function ReceiveModal({
  isOpen,
  isTestnet,
  isLedger,
  isSwapDisabled,
  isOnRampDisabled,
  currentAccountId,
  accountTitle,
  hasMultipleAccounts,
}: StateProps) {
  const { closeReceiveModal, switchAccount } = getActions();

  const lang = useLang();
  const {
    renderingKey, nextKey, updateNextKey, openSelector, closeSelector,
  } = useAccountSwitcherScreen(isOpen, currentAccountId);

  const isSwapAllowed = !isTestnet && !isLedger && !isSwapDisabled;
  const isOnRampAllowed = !isTestnet && !isOnRampDisabled;
  const modalTitle = lang(isSwapAllowed || isOnRampAllowed ? 'Fund' : 'Add');

  const handleSelectAccount = useLastCallback((accountId: string) => {
    switchAccount({ accountId });
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: AccountSwitcherScreen) {
    switch (currentKey) {
      case AccountSwitcherScreen.Main:
        return (
          <>
            <div className={styles.headerWithSwitcher}>
              <ModalHeader
                title={modalTitle}
                className={styles.receiveHeader}
                onClose={closeReceiveModal}
              />
              {hasMultipleAccounts && currentAccountId && (
                <AccountSwitcherPill
                  accountId={currentAccountId}
                  title={accountTitle}
                  className={styles.accountPill}
                  onClick={openSelector}
                />
              )}
            </div>
            <Content
              isOpen={isOpen && isActive}
              onClose={closeReceiveModal}
            />
          </>
        );
      case AccountSwitcherScreen.Selector:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            onAccountSelect={handleSelectAccount}
            onBack={closeSelector}
            onClose={closeReceiveModal}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      onClose={closeReceiveModal}
      onCloseAnimationEnd={updateNextKey}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { isSwapDisabled } = global.restrictions;
  const isLedger = selectIsHardwareAccount(global);

  return {
    isOpen: global.isReceiveModalOpen,
    isTestnet: global.settings.isTestnet,
    isSwapDisabled,
    // The title claims the modal can do more than receive, so it asks whether this account has a chain to buy on
    isOnRampDisabled: !selectDefaultOnRampChain(global),
    isLedger,
    currentAccountId: selectCurrentAccountId(global),
    accountTitle: selectCurrentAccount(global)?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(ReceiveModal));
