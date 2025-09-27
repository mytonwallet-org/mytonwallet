import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import SafetyRulesContent from '../common/backup/SafetyRulesContent';
import Header from './Header';

import styles from './Auth.module.scss';

interface OwnProps {
  isActive?: boolean;
}

const AuthSafetyRules = ({ isActive }: OwnProps) => {
  const { resetAuth, openMnemonicPage } = getActions();

  const lang = useLang();
  const triggerElementRef = useRef<HTMLDivElement>();
  const [firstChecked, setFirstChecked] = useState(false);
  const [secondChecked, setSecondChecked] = useState(false);
  const [thirdChecked, setThirdChecked] = useState(false);

  useHistoryBack({ isActive, onBack: resetAuth });

  return (
    <div className={styles.wrapper}>
      <Header
        isActive={isActive}
        title={lang('Create Backup')}
        topTargetRef={triggerElementRef}
        onBackClick={resetAuth}
      />

      <div className={buildClassName(styles.container, styles.container_scrollable, 'custom-scroll')}>
        <SafetyRulesContent
          isActive={isActive}
          isFullSizeButton
          withHeader
          headerRef={triggerElementRef}
          customStickerClassName={styles.topSticker}
          customButtonWrapperClassName={styles.buttons}
          textFirst={lang('$safety_rules_one')}
          textSecond={lang('$safety_rules_two')}
          textThird={lang('$safety_rules_three')}
          isFirstCheckboxSelected={firstChecked}
          onFirstCheckboxClick={setFirstChecked}
          isSecondCheckboxSelected={secondChecked}
          onSecondCheckboxClick={setSecondChecked}
          isThirdCheckboxSelected={thirdChecked}
          onThirdCheckboxClick={setThirdChecked}
          onSubmit={openMnemonicPage}
        />
      </div>
    </div>
  );
};

export default memo(AuthSafetyRules);
