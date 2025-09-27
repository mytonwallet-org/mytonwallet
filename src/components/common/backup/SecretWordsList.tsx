import React, { memo } from '../../../lib/teact/teact';

import renderText from '../../../global/helpers/renderText';
import buildClassName from '../../../util/buildClassName';
import { copyTextToClipboard } from '../../../util/clipboard';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './BackUpContent.module.scss';

interface OwnProps {
  mnemonic?: string[];
}

function SecretWordsList({
  mnemonic,
}: OwnProps) {
  const lang = useLang();
  const [isWarningOpen, showWarning, hideWarning] = useFlag();

  const handleCopy = useLastCallback(() => {
    hideWarning();

    void copyTextToClipboard(mnemonic!.join(' '));
  });

  return (
    <>
      <div className={styles.info}>
        {renderText(lang('$mnemonic_list_description'))}
      </div>
      <div className={styles.warning}>
        {renderText(lang('$mnemonic_warning'))}
      </div>

      <Button isText className={styles.copyButton} onClick={showWarning}>
        <i className={buildClassName(styles.copyButtonIcon, 'icon-copy-bold')} aria-hidden />
        {lang('Copy to Clipboard')}
      </Button>

      <ol className={styles.words}>
        {mnemonic?.map((word, i) => (

          <li key={i} className={styles.word}>{word}</li>
        ))}
      </ol>

      <Modal
        isOpen={isWarningOpen}
        isCompact
        title={lang('Security Warning')}
        onClose={hideWarning}
      >
        <p className={styles.text}>{renderText(lang('$copy_mnemonic_warning'))}</p>
        <p className={buildClassName(styles.text, styles.warningText)}>
          {lang('Other apps will be able to read your recovery phrase!')}
        </p>

        <div className={buildClassName(modalStyles.footerButtons, modalStyles.footerButtonsVertical)}>
          <Button isPrimary onClick={hideWarning} className={modalStyles.buttonFullWidth}>
            {lang('Go back to Words')}
          </Button>
          <Button isDestructive onClick={handleCopy} className={modalStyles.buttonFullWidth}>
            {lang('I’m sure. Copy anyway')}
          </Button>
        </div>
      </Modal>
    </>
  );
}

export default memo(SecretWordsList);
