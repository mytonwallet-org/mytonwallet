import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { UserSwapToken, UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenSelector from '../common/TokenSelector';
import Button from '../ui/Button';

import styles from './Settings.module.scss';

interface OwnProps {
  isActive?: boolean;
  isInsideModal?: boolean;
  onBackClick: NoneToVoidFunction;
}

function SettingsTokenList({
  isActive,
  isInsideModal,
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

  function renderHeader() {
    return (
      <div className={buildClassName(styles.header, isInsideModal && styles.headerInsideModal)}>
        <Button
          isSimple
          isText
          className={buildClassName(styles.headerBack, isInsideModal && styles.isInsideModal)}
          onClick={onBackClick}
        >
          <i className={buildClassName(styles.iconChevron, 'icon-chevron-left')} aria-hidden />
          <span>{lang('Back')}</span>
        </Button>
        <span className={styles.headerTitle}>{lang('Select Token')}</span>
      </div>
    );
  }

  return (
    <div className={buildClassName(styles.slide, styles.withTopSpace)}>
      <TokenSelector
        isActive={isActive}
        shouldHideMyTokens
        shouldHideNotSupportedTokens
        header={renderHeader()}
        onTokenSelect={handleTokenSelect}
        onBack={onBackClick}
        onClose={onBackClick}
      />
    </div>
  );
}

export default memo(SettingsTokenList);
