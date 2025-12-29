import React, { memo, useState } from '../../../lib/teact/teact';

import buildClassName from '../../../util/buildClassName';
import { getChainTitle } from '../../../util/chain';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useScrolledState from '../../../hooks/useScrolledState';

import SafetyRulesContent from '../../common/backup/SafetyRulesContent';
import Button from '../../ui/Button';
import ModalHeader from '../../ui/ModalHeader';

import settingsStyles from '../Settings.module.scss';
import styles from './Backup.module.scss';

interface OwnProps {
  isActive?: boolean;
  onBackClick: () => void;
  onSubmit: () => void;
  isInsideModal?: boolean;
  backupType: 'key' | 'words';
}

function BackupSafetyRules({
  isActive,
  onBackClick,
  isInsideModal,
  onSubmit,
  backupType,
}: OwnProps) {
  const lang = useLang();

  const [writedownAccepted, setWritedownAccepted] = useState(false);
  const [openWalletAccepted, setOpenWalletAccepted] = useState(false);
  const [canBeStolenAccepted, setCanBeStolenAccepted] = useState(false);

  const handleBackClick = useLastCallback(() => {
    setWritedownAccepted(false);
    setOpenWalletAccepted(false);
    setCanBeStolenAccepted(false);
    onBackClick();
  });

  useHistoryBack({
    isActive,
    onBack: onBackClick,
  });

  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  return (
    <div className={settingsStyles.slide}>
      {isInsideModal ? (
        <ModalHeader
          title={lang('Safety Rules')}
          withNotch={isScrolled}
          onBackButtonClick={handleBackClick}
          className={settingsStyles.modalHeader}
        />
      ) : (
        <div className={buildClassName(settingsStyles.header, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
          <Button isSimple isText onClick={handleBackClick} className={settingsStyles.headerBack}>
            <i className={buildClassName(settingsStyles.iconChevron, 'icon-chevron-left')} aria-hidden />
            <span>{lang('Back')}</span>
          </Button>
          <span className={settingsStyles.headerTitle}>{lang('Safety Rules')}</span>
        </div>
      )}
      <div
        className={buildClassName(settingsStyles.content, styles.content)}
        onScroll={handleContentScroll}
      >
        <SafetyRulesContent
          isActive={isActive}
          isFullSizeButton
          textFirst={lang(
            backupType === 'key'
              ? '$safety_rules_private_key_one'
              : '$safety_rules_one',
            { chain: getChainTitle('ton') },
          )}
          textSecond={lang(
            backupType === 'key'
              ? '$safety_rules_private_key_two'
              : '$safety_rules_two',
          )}
          textThird={lang(
            backupType === 'key'
              ? '$safety_rules_private_key_three'
              : '$safety_rules_three',
          )}
          isFirstCheckboxSelected={writedownAccepted}
          onFirstCheckboxClick={setWritedownAccepted}
          isSecondCheckboxSelected={openWalletAccepted}
          onSecondCheckboxClick={setOpenWalletAccepted}
          isThirdCheckboxSelected={canBeStolenAccepted}
          onThirdCheckboxClick={setCanBeStolenAccepted}
          onSubmit={onSubmit}
        />
      </div>
    </div>
  );
}

export default memo(BackupSafetyRules);
