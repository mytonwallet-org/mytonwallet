import React, { memo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import { SettingsState } from '../../../../global/types';

import { IS_EXPLORER } from '../../../../config';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import styles from './Warnings.module.scss';

interface StateProps {
  isTestnet?: boolean;
}

function TestnetWarning({ isTestnet }: StateProps) {
  const { openSettingsWithState } = getActions();
  const { isPortrait } = useDeviceScreen();
  const lang = useLang();

  const handleOpenDeveloperMenu = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.Developer });
  });

  if (!isTestnet) return undefined;

  return (
    <div className={isPortrait ? styles.testnetPortraitContainer : styles.testnetContainer}>
      <button
        type="button"
        className={styles.testnetWarning}
        disabled={IS_EXPLORER}
        onClick={handleOpenDeveloperMenu}
      >
        {lang('Testnet Version')}
      </button>
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  return {
    isTestnet: global.settings.isTestnet,
  };
})(TestnetWarning));
