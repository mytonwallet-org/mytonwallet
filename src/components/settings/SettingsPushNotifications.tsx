import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { Account, AccountSettings, AccountType, GlobalState } from '../../global/types';

import { MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT } from '../../config';
import { selectOrderedAccounts } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';

import AccountButton from '../common/AccountButton';
import AccountButtonWrapper from '../common/AccountButtonWrapper';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  handleBackClick: () => void;
  isInsideModal?: boolean;
}

interface StateProps {
  orderedAccounts: Array<[string, Account]>;
  canPlaySounds?: boolean;
  settingsByAccountId?: Record<string, AccountSettings>;
  pushNotifications: GlobalState['pushNotifications'];
}

function SettingsPushNotifications({
  isActive,
  handleBackClick,
  orderedAccounts,
  canPlaySounds,
  pushNotifications: {
    enabledAccounts,
    isAvailable: arePushNotificationsAvailable,
  },
  isInsideModal,
  settingsByAccountId,
}: OwnProps & StateProps) {
  const lang = useLang();

  const { toggleNotifications, toggleNotificationAccount, toggleCanPlaySounds } = getActions();
  const arePushNotificationsEnabled = enabledAccounts.length > 0;
  const headerTitle = arePushNotificationsAvailable ? lang('Notifications & Sounds') : lang('Sounds');
  const enabledAccountsSet = useMemo(() => new Set(enabledAccounts), [enabledAccounts]);

  const handlePushNotificationsToggle = useLastCallback(() => {
    toggleNotifications({ isEnabled: !arePushNotificationsEnabled });
  });

  const handleCanPlaySoundToggle = useLastCallback(() => {
    toggleCanPlaySounds({ isEnabled: !canPlaySounds });
  });

  useHistoryBack({
    isActive,
    onBack: handleBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  function renderAccount(
    accountId: string,
    byChain: Account['byChain'],
    accountType: AccountType,
    title?: string,
  ) {
    const hasSupportedChain = useMemo(() => {
      return (Object.keys(byChain) as (keyof typeof byChain)[])
        .some((chain) => getChainConfig(chain).doesSupportPushNotifications);
    }, [byChain]);

    const onClick = !hasSupportedChain ? undefined : () => {
      toggleNotificationAccount({ accountId });
    };

    const { cardBackgroundNft } = settingsByAccountId?.[accountId] || {};

    const isActive = enabledAccountsSet.has(accountId);
    const isDisabled = !isActive && enabledAccounts.length >= MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT;

    return (
      <AccountButton
        key={accountId}
        accountId={accountId}
        byChain={byChain}
        title={title}
        className={buildClassName(
          styles.account,
          isDisabled ? styles.accountDisabled : undefined,
        )}
        titleClassName={styles.pushAccountName}
        accountType={accountType}
        withCheckbox
        isLoading={isDisabled}
        isActive={isActive}

        onClick={onClick}
        cardBackgroundNft={cardBackgroundNft}
      />
    );
  }

  function renderAccounts() {
    return (
      <AccountButtonWrapper
        accountLength={orderedAccounts.length}
        className={styles.settingsBlock}
      >
        {orderedAccounts.map(
          ([accountId, { title, byChain, type }]) => {
            return renderAccount(accountId, byChain, type, title);
          },
        )}
      </AccountButtonWrapper>
    );
  }

  return (
    <div className={styles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={headerTitle}
          withNotch={isScrolled}
          onBackButtonClick={handleBackClick}
          className={styles.modalHeader}
        />
      ) : (
        <div className={buildClassName(styles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={handleBackClick} className={styles.headerBack}>
            <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={styles.headerTitle}>{headerTitle}</span>
        </div>
      )}
      <div
        className={buildClassName(styles.content, 'custom-scroll')}
        onScroll={handleContentScroll}
      >
        {arePushNotificationsAvailable && (
          <>
            <div className={styles.settingsBlock}>
              <div className={buildClassName(styles.item, styles.item_small)} onClick={handlePushNotificationsToggle}>
                {lang('Push Notifications')}

                <Switcher
                  className={styles.menuSwitcher}
                  label={lang('Push Notifications')}
                  checked={arePushNotificationsEnabled}
                />
              </div>
            </div>
            <p className={styles.blockTitle}>{
              lang(
                'Select up to %count% wallets for notifications',
                { count: MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT },
              )
            }
            </p>
            {renderAccounts()}
          </>
        )}
        <div className={styles.settingsBlock}>
          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleCanPlaySoundToggle}>
            {lang('Play Sounds')}

            <Switcher
              className={styles.menuSwitcher}
              label={lang('Play Sounds')}
              checked={canPlaySounds}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const orderedAccounts = selectOrderedAccounts(global);

  return {
    orderedAccounts,
    canPlaySounds: global.settings.canPlaySounds,
    pushNotifications: global.pushNotifications,
    settingsByAccountId: global.settings.byAccountId,
  };
})(SettingsPushNotifications));
