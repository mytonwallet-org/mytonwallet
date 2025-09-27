import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import SecretWordsList from '../common/backup/SecretWordsList';
import Button from '../ui/Button';
import Header from './Header';

import modalStyles from '../ui/Modal.module.scss';

type OwnProps = {
  isActive?: boolean;
  mnemonic?: string[];
  onClose: NoneToVoidFunction;
  onNext?: NoneToVoidFunction;
};

function MnemonicList({
  isActive, mnemonic, onNext, onClose,
}: OwnProps) {
  const lang = useLang();
  const wordsCount = mnemonic?.length || 0;

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  return (
    <div className={modalStyles.transitionContentWrapper}>
      <Header
        isActive={isActive}
        title={lang('%1$d Secret Words', wordsCount) as string}
        onBackClick={onClose}
      />

      <div className={buildClassName(modalStyles.transitionContent, 'custom-scroll')}>
        <SecretWordsList mnemonic={mnemonic} />
        {onNext && (
          <div className={modalStyles.buttons}>
            <Button isPrimary onClick={onNext}>{lang('Let\'s Check')}</Button>
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(MnemonicList);
