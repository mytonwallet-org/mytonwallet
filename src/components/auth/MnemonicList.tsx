import React, { memo } from '../../lib/teact/teact';

import { NEW_APP_URL, PRODUCTION_URL } from '../../config';
import buildClassName from '../../util/buildClassName';
import { IS_LEGACY_APP_HOST } from '../../util/windowEnvironment';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import SecretWordsList from '../common/backup/SecretWordsList';
import Button from '../ui/Button';
import Header from './Header';

import modalStyles from '../ui/Modal.module.scss';

const NEW_DOMAIN = new URL(PRODUCTION_URL).hostname;

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

  const handleOpenNewDomain = useLastCallback(() => {
    window.open(NEW_APP_URL, '_blank', 'noopener');
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
        {IS_LEGACY_APP_HOST && (
          <div className={modalStyles.buttons}>
            <Button isPrimary onClick={handleOpenNewDomain}>
              {lang('Open %new_domain%', { new_domain: NEW_DOMAIN })}
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}

export default memo(MnemonicList);
