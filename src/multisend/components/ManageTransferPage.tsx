import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import type { TransferRow } from '../types';

import buildClassName from '../../util/buildClassName';
import { vibrate } from '../../util/haptics';
import { isValidAddressOrDomain } from '../../util/isValidAddress';
import { trimStringByMaxBytes } from '../../util/text';
import { validateAndProcessTransfer } from '../utils/transferValidation';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AddressInput from '../../components/ui/AddressInput';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import RichNumberInput from '../../components/ui/RichNumberInput';
import Transition from '../../components/ui/Transition';

import styles from './ManageTransferPage.module.scss';

interface OwnProps {
  isActive?: boolean;
  onBack: () => void;
  onSubmit: (transfer: TransferRow, index?: number) => void;
  onDelete?: (index: number) => void;
  editingTransfer?: TransferRow;
  editingIndex?: number;
}

const COMMENT_MAX_SIZE_BYTES = 5000;

function ManageTransferPage({ isActive, onBack, onSubmit, onDelete, editingTransfer, editingIndex }: OwnProps) {
  const lang = useLang();

  const [toAddress, setToAddress] = useState('');
  const [amount, setAmount] = useState('');
  const [tokenIdentifier, setTokenIdentifier] = useState('');
  const [comment, setComment] = useState<string>();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [tokenError, setTokenError] = useState<string | undefined>();

  useHistoryBack({
    isActive,
    onBack,
  });

  const isEditing = Boolean(editingTransfer);

  useEffect(() => {
    if (isActive && editingTransfer) {
      setToAddress(editingTransfer.receiver);
      setAmount(editingTransfer.amount);
      setTokenIdentifier(editingTransfer.tokenIdentifier);
      setComment(editingTransfer.comment);
      setTokenError(undefined);
    } else if (isActive) {
      setToAddress('');
      setAmount('');
      setTokenIdentifier('');
      setComment('');
      setTokenError(undefined);
    }
  }, [editingTransfer, isActive]);

  const isAddressValid = isValidAddressOrDomain(toAddress, 'ton');
  const isAmountValid = amount && Number(amount) > 0;
  const canSubmit = isAddressValid && isAmountValid && tokenIdentifier.length > 0 && !isSubmitting;

  const shouldShowDelete = isEditing && (!toAddress.trim() || !amount.trim());

  const handleAddressInput = useLastCallback((newToAddress: string) => {
    setToAddress(newToAddress);
  });

  const handleAmountChange = useLastCallback((value?: string) => {
    setAmount(value || '');
  });

  const handleTokenInput = useLastCallback((value: string) => {
    setTokenIdentifier(value);
    setTokenError(undefined);
  });

  const handleCommentInput = useLastCallback((value: string) => {
    const trimmedValue = trimStringByMaxBytes(value, COMMENT_MAX_SIZE_BYTES);
    setComment(trimmedValue);
  });

  const handleSubmit = useLastCallback(async (e: React.FormEvent) => {
    e.preventDefault();

    if (!canSubmit) return;

    setIsSubmitting(true);
    void vibrate();

    try {
      const validationResult = await validateAndProcessTransfer({
        receiver: toAddress,
        amount,
        tokenIdentifier,
        comment,
      });

      if (!validationResult.isValid || !validationResult.processedTransfer) {
        if (validationResult.error && validationResult.error.includes('token')) {
          setTokenError('Invalid token identifier');
        } else {
          // eslint-disable-next-line no-console
          console.error('Transfer validation failed:', validationResult.error);
        }
        return;
      }

      onSubmit(validationResult.processedTransfer, editingIndex);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('Transfer processing failed:', err);
    } finally {
      setIsSubmitting(false);
    }
  });

  const handleDelete = useLastCallback(() => {
    if (editingIndex !== undefined && onDelete) {
      void vibrate();
      onDelete(editingIndex);
    }
  });

  const handleBackClick = useLastCallback(() => {
    onBack();
  });

  return (
    <div className={buildClassName(styles.container, isEditing && styles.editing)}>
      <form className={styles.form} onSubmit={handleSubmit}>
        <div>
          <AddressInput
            label={lang('Recipient Address')}
            chain="ton"
            withCurrentAccount
            value={toAddress}
            address={toAddress}
            addressName=""
            onInput={handleAddressInput}
            onClose={onBack}
          />
        </div>

        <div>
          <RichNumberInput
            id="multisend-amount-input"
            labelText={lang('Amount')}
            value={amount}
            onChange={handleAmountChange}
          />
        </div>

        <div>
          <Input
            id="multisend-token-input"
            label={lang('Token')}
            value={tokenIdentifier}
            placeholder={lang('Token ticker or address')}
            hasError={!!tokenError}
            error={tokenError}
            onInput={handleTokenInput}
          />
        </div>

        <div>
          <Input
            id="multisend-comment-input"
            label={lang('Comment')}
            value={comment}
            placeholder={lang('Optional')}
            isMultiline={true}
            onInput={handleCommentInput}
          />
        </div>

        <div className={styles.footer}>
          <div className={styles.buttons}>
            <Button onClick={handleBackClick} className={styles.button}>
              {lang('Back')}
            </Button>
            <Button
              isPrimary={!shouldShowDelete}
              isSubmit={!shouldShowDelete}
              isDisabled={!shouldShowDelete && !canSubmit}
              isDestructive={shouldShowDelete}
              isLoading={isSubmitting}
              className={styles.button}
              onClick={shouldShowDelete ? handleDelete : undefined}
            >
              <Transition name="fade" activeKey={shouldShowDelete ? 1 : 0} slideClassName={styles.transitionSlide}>
                {
                  shouldShowDelete
                    ? lang('Delete')
                    : isEditing
                      ? lang('Save')
                      : lang('Add')
                }
              </Transition>
            </Button>
          </div>
        </div>
      </form>
    </div>
  );
}

export default memo(ManageTransferPage);
