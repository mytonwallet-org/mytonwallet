import React, { memo, useEffect, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNetwork } from '../../api/types';
import type { Account, AuthType, DeveloperSettingsOverrides } from '../../global/types';
import type { DropdownItem } from '../ui/Dropdown';

import {
  IS_GRAM_WALLET,
  IS_PERPS_ENABLED,
  SHOULD_CLEANUP_LEGACY_AUTH,
} from '../../config';
import { CAN_DOWNLOAD_LOGS, exportLogs } from '../../global/helpers/logsExport';
import {
  selectCurrentAccountId,
  selectDeveloperSettingsOverrides,
  selectIsMultichainAccount,
  selectSeasonalThemeOverride,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import getTestId from '../../util/getTestId';
import { callApi } from '../../api';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import PerpsLabModal from '../perps/PerpsLabModal';
import Button from '../ui/Button';
import Dropdown from '../ui/Dropdown';
import Modal from '../ui/Modal';
import Switcher from '../ui/Switcher';

import styles from './Settings.module.scss';

interface OwnProps {
  isOpen: boolean;
  isTestnet?: boolean;
  isCopyStorageEnabled?: boolean;
  isViewMode?: boolean;
  onShowAllWalletVersions: NoneToVoidFunction;
  onOpenPermissions: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  currentAccountId?: string;
  accountsById?: Record<string, Account>;
  canViewAllWalletVersions: boolean;
  authTypes?: AuthType[];
  seasonalThemeOverride?: DeveloperSettingsOverrides['seasonalTheme'];
  isGramDiamondEnabled?: true;
}

type SeasonalThemeOverrideOption = NonNullable<DeveloperSettingsOverrides['seasonalTheme']> | 'default';

const NETWORK_OPTIONS: DropdownItem<ApiNetwork>[] = [{
  value: 'mainnet',
  name: 'Mainnet',
}, {
  value: 'testnet',
  name: 'Testnet',
}];

const SEASONAL_THEME_OVERRIDE_OPTIONS: DropdownItem<SeasonalThemeOverrideOption>[] = [{
  value: 'default',
  name: 'Auto',
}, {
  value: '__undefined',
  name: 'None',
}, {
  value: 'newYear',
  name: 'New Year',
}, {
  value: 'valentine',
  name: 'Valentine',
}];

function SettingsDeveloperOptions({
  isOpen,
  isTestnet,
  isCopyStorageEnabled,
  isViewMode,
  onShowAllWalletVersions,
  onOpenPermissions,
  onClose,
  currentAccountId,
  accountsById,
  canViewAllWalletVersions,
  authTypes,
  seasonalThemeOverride,
  isGramDiamondEnabled,
}: OwnProps & StateProps) {
  const {
    startChangingNetwork,
    setDeveloperSettingsOverride,
    closeSettings,
    openAddAccountModal,
    copyStorageData,
    showToast,
    rollbackEnclaveMigration,
  } = getActions();

  const lang = useLang();
  const [isPerpsLabOpen, openPerpsLab, closePerpsLab] = useFlag(false);
  const [hasLegacyData, setHasLegacyData] = useState(false);
  const currentNetwork = NETWORK_OPTIONS[isTestnet ? 1 : 0].value;

  // Check if legacy data exists
  useEffect(() => {
    if (isOpen) {
      void callApi('hasLegacyData')
        .then((result) => {
          setHasLegacyData(Boolean(result));
        });
    }
  }, [isOpen]);

  const canRollbackMigration = hasLegacyData && !SHOULD_CLEANUP_LEGACY_AUTH && Boolean(authTypes?.length);

  const handleNetworkChange = useLastCallback((newNetwork: ApiNetwork) => {
    startChangingNetwork({ network: newNetwork });
    onClose();
  });

  const handleAddTonOnlyWallet = useLastCallback(() => {
    onClose();
    closeSettings();
    openAddAccountModal({ forceAddingTonOnlyAccount: true });
  });

  const handleSeasonalThemeOverrideChange = useLastCallback((newValue: SeasonalThemeOverrideOption) => {
    setDeveloperSettingsOverride({
      key: 'seasonalTheme',
      value: newValue === 'default' ? undefined : newValue,
    });
  });

  const handleGramDiamondToggle = useLastCallback(() => {
    setDeveloperSettingsOverride({
      key: 'isGramDiamondEnabled',
      value: isGramDiamondEnabled ? undefined : true,
    });
  });

  const handleDownloadLogs = useLastCallback(async () => {
    const isCopied = await exportLogs({ currentAccountId, accountsById });

    if (isCopied) {
      showToast({ message: lang('Logs Copied'), icon: 'icon-copy' });
      onClose();
    }
  });

  const handleRollbackMigration = useLastCallback(() => {
    rollbackEnclaveMigration();

    onClose();
  });

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        noBackdropClose
        isCompact
        title={lang('Developer Options')}
      >
        <div className={styles.settingsBlock}>
          <Dropdown
            label={lang('Network')}
            items={NETWORK_OPTIONS}
            selectedValue={currentNetwork}
            theme="light"
            arrow="chevron"
            className={buildClassName(styles.item, styles.item_small)}
            onChange={handleNetworkChange}
          />

          <div className={buildClassName(styles.item, styles.item_small)} onClick={handleAddTonOnlyWallet}>
            <span className={styles.itemTitle}>{lang('Create TON-Only Wallet')}</span>

            <i className={buildClassName(styles.iconChevronRight, 'icon-plus')} aria-hidden />
          </div>

          {IS_PERPS_ENABLED && (
            <div className={buildClassName(styles.item, styles.item_small)} onClick={openPerpsLab}>
              <span className={styles.itemTitle}>Perps Lab</span>

              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
          )}

          {!isViewMode && (
            <div className={buildClassName(styles.item, styles.item_small)} onClick={onOpenPermissions}>
              <span className={styles.itemTitle}>{lang('Permissions')}</span>

              <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />
            </div>
          )}

          <div
            className={buildClassName(
              styles.item,
              styles.item_small,
              !canViewAllWalletVersions && styles.item_disabled,
            )}
            onClick={onShowAllWalletVersions}
          >
            <span className={styles.itemTitle}>{lang('All Wallet Versions')}</span>

            <div className={styles.itemInfo}>
              {canViewAllWalletVersions ? (
                <i className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')} aria-hidden />

              ) : (
                <>
                  <span className={styles.small}>{lang('Multichain')}</span>
                  <i className={buildClassName(styles.iconChevronRight, 'icon-lock')} aria-hidden />
                </>
              )}
            </div>
          </div>
        </div>

        <p className={styles.blockTitle}>{lang('Overrides')}</p>
        <div className={styles.settingsBlock}>
          <Dropdown
            label={lang('Seasonal Theme Override')}
            items={SEASONAL_THEME_OVERRIDE_OPTIONS}
            selectedValue={seasonalThemeOverride ?? 'default'}
            theme="light"
            arrow="chevron"
            className={buildClassName(styles.item, styles.item_small)}
            onChange={handleSeasonalThemeOverrideChange}
          />

          {!IS_GRAM_WALLET && (
            <div className={buildClassName(styles.item, styles.item_small)} onClick={handleGramDiamondToggle}>
              <span className={styles.itemTitle}>{lang('3D Gram Diamond')}</span>

              <Switcher
                className={styles.menuSwitcher}
                label={lang('3D Gram Diamond')}
                checked={Boolean(isGramDiamondEnabled)}
              />
            </div>
          )}
        </div>

        {(isCopyStorageEnabled || canRollbackMigration) && (
          <>
            <p className={styles.blockTitle}>{lang('Dangerous')}</p>
            <div className={styles.settingsBlock}>
              {isCopyStorageEnabled && (
                <div className={buildClassName(styles.item, styles.item_small)} onClick={() => copyStorageData()}>
                  <span className={styles.itemTitle}>{lang('Copy Storage Data')}</span>

                  <i className={buildClassName(styles.iconChevronRight, 'icon-copy')} aria-hidden />
                </div>
              )}
              {canRollbackMigration && (
                <div className={buildClassName(styles.item, styles.item_small)} onClick={handleRollbackMigration}>
                  {lang('Rollback Migration')}

                  <i className={buildClassName(styles.iconChevronRight, 'icon-revert')} aria-hidden />
                </div>
              )}
            </div>
          </>
        )}

        <div className={buildClassName(styles.settingsBlock)}>
          <div
            className={buildClassName(styles.item, styles.item_small)}
            data-testid={getTestId('debug_view_logs')}
            onClick={handleDownloadLogs}
          >
            {
              !CAN_DOWNLOAD_LOGS
                ? (
                  <>
                    <span className={styles.itemTitle}>{lang('Copy Logs')}</span>

                    <i className={buildClassName(styles.iconChevronRight, 'icon-copy')} aria-hidden />
                  </>
                ) : <span className={styles.itemTitle}>{lang('Download Logs')}</span>
            }
          </div>
        </div>

        <Button
          className={styles.developerCloseButton}
          onClick={onClose}
        >
          {lang('Close')}
        </Button>
      </Modal>
      {IS_PERPS_ENABLED && <PerpsLabModal isOpen={isPerpsLabOpen} onClose={closePerpsLab} />}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const currentAccountId = selectCurrentAccountId(global);
  const accountsById = global.accounts?.byId;
  const canViewAllWalletVersions = !selectIsMultichainAccount(global, currentAccountId!);

  return {
    currentAccountId,
    accountsById,
    canViewAllWalletVersions,
    authTypes: global.authTypes,
    seasonalThemeOverride: selectSeasonalThemeOverride(global),
    isGramDiamondEnabled: selectDeveloperSettingsOverrides(global)?.isGramDiamondEnabled,
  };
})(SettingsDeveloperOptions));
