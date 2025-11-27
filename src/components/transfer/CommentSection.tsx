import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiChain } from '../../api/types';

import renderText from '../../global/helpers/renderText';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Dropdown from '../ui/Dropdown';
import Input from '../ui/Input';
import InteractiveTextField from '../ui/InteractiveTextField';

import styles from './Transfer.module.scss';

const COMMENT_DROPDOWN_ITEMS = [
  { value: 'raw', name: 'Comment or Memo' },
  { value: 'encrypted', name: 'Encrypted Message' },
];

interface OwnProps {
  comment: string;
  shouldEncrypt?: boolean;
  binPayload?: string;
  stateInit?: string;
  chain?: ApiChain;
  isStatic?: boolean;
  isCommentRequired?: boolean;
  isEncryptedCommentSupported: boolean;
  onCommentChange: (value: string) => void;
}

function CommentSection({
  comment,
  shouldEncrypt,
  binPayload,
  stateInit,
  chain,
  isStatic,
  isCommentRequired,
  isEncryptedCommentSupported,
  onCommentChange,
}: OwnProps) {
  const { setTransferShouldEncrypt } = getActions();

  const lang = useLang();

  const handleCommentOptionsChange = useLastCallback((option: string) => {
    setTransferShouldEncrypt({ shouldEncrypt: option === 'encrypted' });
  });

  const dropdownItems = useMemo(
    () => isEncryptedCommentSupported ? COMMENT_DROPDOWN_ITEMS : COMMENT_DROPDOWN_ITEMS.slice(0, 1),
    [isEncryptedCommentSupported],
  );

  function renderCommentLabel() {
    return (
      <Dropdown
        items={dropdownItems}
        selectedValue={COMMENT_DROPDOWN_ITEMS[shouldEncrypt ? 1 : 0].value}
        theme="inherit"
        menuPositionX="left"
        shouldTranslateOptions
        onChange={handleCommentOptionsChange}
      />
    );
  }

  if (binPayload || stateInit) {
    return (
      <>
        {binPayload && (
          <>
            <div className={styles.label}>{lang('Signing Data')}</div>
            <InteractiveTextField
              text={binPayload}
              copyNotification={lang('Data was copied!')}
              className={styles.addressWidget}
            />
          </>
        )}

        {stateInit && (
          <>
            <div className={styles.label}>{lang('Contract Initialization Data')}</div>
            <InteractiveTextField
              text={stateInit}
              copyNotification={lang('Data was copied!')}
              className={styles.addressWidget}
            />
          </>
        )}

        <div className={styles.error}>
          {renderText(lang('$signature_warning'))}
        </div>
      </>
    );
  }

  return (
    <Input
      wrapperClassName={styles.commentInputWrapper}
      className={isStatic ? styles.inputStatic : undefined}
      label={renderCommentLabel()}
      placeholder={isCommentRequired ? lang('Required') : lang('Optional')}
      value={comment}
      isMultiline
      onInput={onCommentChange}
      isRequired={isCommentRequired}
    />
  );
}

export default memo(CommentSection);
