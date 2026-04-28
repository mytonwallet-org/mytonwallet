import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { UserSwapToken, UserToken } from '../../global/types';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenSelector from '../common/TokenSelector';
import SettingsHeader from './SettingsHeader';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

function SettingsTokenList({
  isActive,
  onBackClick,
}: OwnProps) {
  const { addToken } = getActions();

  const lang = useLang();

  const handleTokenSelect = useLastCallback((token: UserToken | UserSwapToken) => {
    addToken({ token: token as UserToken });
  });

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  return (
    <div className={styles.slide}>
      <SettingsHeader title={lang('Select Token')} onBackClick={onBackClick} />
      <div className={styles.tokenListContent}>
        <TokenSelector
          isActive={isActive}
          shouldHideMyTokens
          shouldHideNotSupportedTokens
          noHeader
          searchClassName={styles.tokenListSearch}
          onTokenSelect={handleTokenSelect}
          onBack={onBackClick}
          onClose={onBackClick}
        />
      </div>
    </div>
  );
}

export default memo(SettingsTokenList);
