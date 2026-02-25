import React, { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNetwork } from '../../api/types';
import type { Account, DeveloperSettingsOverrides } from '../../global/types';
import type { Log } from '../../util/logs';
import type { DropdownItem } from '../ui/Dropdown';

import { APP_COMMIT_HASH, APP_ENV, APP_VERSION, IS_CORE_WALLET, IS_EXTENSION, IS_TELEGRAM_APP } from '../../config';
import { selectCurrentAccountId, selectIsMultichainAccount, selectSeasonalThemeOverride } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { copyTextToClipboard } from '../../util/clipboard';
import { getBuildPlatform, getFlagsValue } from '../../util/getBuildPlatform';
import { getPlatform } from '../../util/getPlatform';
import { mapValues } from '../../util/iteratees';
import { getLogs } from '../../util/logs';
import { shareFile } from '../../util/share';
import { IS_IOS } from '../../util/windowEnvironment';
import { callApi } from '../../api';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Dropdown from '../ui/Dropdown';
import Modal from '../ui/Modal';

import styles from './Settings.module.scss';

interface OwnProps {
  isOpen: boolean;
  isTestnet?: boolean;
  isCopyStorageEnabled?: boolean;
  onShowAllWalletVersions: () => void;
  onClose: () => void;
}

interface StateProps {
  currentAccountId?: string;
  accountsById?: Record<string, Account>;
  canViewAllWalletVersions: boolean;
  seasonalThemeOverride?: DeveloperSettingsOverrides['seasonalTheme'];
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

// iOS allows downloading files even in TMA, however, in other platforms,
// downloading files from `blob:https://` schemes is limited by Telegram itself.
// Also, file downloading is limited in extensions.
const CAN_DOWNLOAD_LOGS = IS_IOS || !(IS_EXTENSION || IS_TELEGRAM_APP);

function SettingsDeveloperOptions({
  isOpen,
  isTestnet,
  isCopyStorageEnabled,
  onShowAllWalletVersions,
  onClose,
  currentAccountId,
  accountsById,
  canViewAllWalletVersions,
  seasonalThemeOverride,
}: OwnProps & StateProps) {
  const {
    startChangingNetwork,
    setDeveloperSettingsOverride,
    closeSettings,
    openAddAccountModal,
    copyStorageData,
    showToast,
  } = getActions();
  const lang = useLang();
  const currentNetwork = NETWORK_OPTIONS[isTestnet ? 1 : 0].value;

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

  const handleDownloadLogs = useLastCallback(async () => {
    const logsString = await getLogsString({ currentAccountId, accountsById });

    if (!CAN_DOWNLOAD_LOGS) {
      await copyTextToClipboard(logsString);
      showToast({ message: lang('Logs Copied'), icon: 'icon-copy' });
      onClose();
    } else {
      const filename = `${IS_CORE_WALLET ? 'tonwallet' : 'mytonwallet'}_logs_${new Date().toISOString()}.json`;
      await shareFile(filename, logsString, 'application/json');
    }
  });

  return (
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
          {lang('Create TON-Only Wallet')}

          <i className={buildClassName(styles.iconChevronRight, 'icon-plus')} aria-hidden />
        </div>

        <div
          className={buildClassName(styles.item, styles.item_small, !canViewAllWalletVersions && styles.item_disabled)}
          onClick={onShowAllWalletVersions}
        >
          {lang('All Wallet Versions')}

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
      </div>

      {isCopyStorageEnabled && (
        <>
          <p className={styles.blockTitle}>{lang('Dangerous')}</p>
          <div className={styles.settingsBlock}>
            <div className={buildClassName(styles.item, styles.item_small)} onClick={() => copyStorageData()}>
              {lang('Copy Storage Data')}

              <i className={buildClassName(styles.iconChevronRight, 'icon-copy')} aria-hidden />
            </div>
          </div>
        </>
      )}

      <div className={buildClassName(styles.settingsBlock)}>
        <div className={buildClassName(styles.item, styles.item_small)} onClick={handleDownloadLogs}>
          {
            !CAN_DOWNLOAD_LOGS
              ? (
                <>
                  {lang('Copy Logs')}

                  <i className={buildClassName(styles.iconChevronRight, 'icon-copy')} aria-hidden />
                </>
              ) : lang('Download Logs')
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
    seasonalThemeOverride: selectSeasonalThemeOverride(global),
  };
})(SettingsDeveloperOptions));

async function getLogsString({
  currentAccountId,
  accountsById,
}: Partial<StateProps>) {
  const accountsInfo = accountsById && mapValues(accountsById, (account) => ({
    type: account.type,
    addressByChain: mapValues(account.byChain, (accountChain) => accountChain.address),
  }));

  const [mainLogs, apiLogs = []] = await Promise.all([
    getLogs(),
    callApi('getLogs'),
  ]);

  const time = new Date();
  const timezoneOffset = -time.getTimezoneOffset();

  return JSON.stringify(
    {
      time,
      timezone: `UTC${timezoneOffset < 0 ? '-' : '+'}${Math.abs(timezoneOffset) / 60}`,
      environment: APP_ENV,
      version: APP_VERSION,
      commit: APP_COMMIT_HASH,
      platform: getPlatform(),
      navigatorPlatform: navigator.platform,
      userAgent: navigator.userAgent,
      build: getBuildPlatform(),
      flags: getFlagsValue(),
      currentAccountId,
      accountsInfo,
      logs: [
        ...mainLogs.map((log: Log) => ({ ...log, context: 'main' })),
        ...apiLogs.map((log: Log) => ({ ...log, context: 'api' })),
      ]
        .sort((a, b) => a.time - b.time)
        .map((log) => ({ ...log, time: new Date(log.time).toISOString() })),
    },
    undefined,
    2,
  );
}
