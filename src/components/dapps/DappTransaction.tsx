import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiDappTransfer, ApiToken } from '../../api/types';

import { TONCOIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import isEmptyObject from '../../util/isEmptyObject';
import { isNftTransferPayload, isTokenTransferPayload } from '../../util/ton/transfer';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import NftInfo from '../transfer/NftInfo';
import InteractiveTextField from '../ui/InteractiveTextField';
import ModalHeader from '../ui/ModalHeader';
import DappAmountField from './DappAmountField';
import DappTransactionPayload from './DappTransactionPayload';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface OwnProps {
  transaction?: ApiDappTransfer;
  tokensBySlug: Record<string, ApiToken>;
  isActive: boolean;
  onClose: NoneToVoidFunction;
  onBack: NoneToVoidFunction;
}

function DappTransaction({ transaction, tokensBySlug, isActive, onClose, onBack }: OwnProps) {
  const lang = useLang();

  useHistoryBack({ isActive, onBack });

  return (
    <>
      <ModalHeader
        title={lang('Transfer Info')}
        onBackButtonClick={onBack}
        onClose={onClose}
      />
      <div className={buildClassName(modalStyles.transitionContent, styles.transactionContent)}>
        {transaction && (
          <DappTransactionContent
            transaction={transaction}
            tokensBySlug={tokensBySlug}
          />
        )}
      </div>
    </>
  );
}

export default memo(DappTransaction);

function DappTransactionContent({
  transaction,
  tokensBySlug,
}: Required<Pick<OwnProps, 'transaction' | 'tokensBySlug'>>) {
  const lang = useLang();

  const amountBySlug = useMemo(() => {
    const { amount: tonAmount, payload } = transaction;
    const amountBySlug: Record<string, bigint> = {};

    if (isTokenTransferPayload(payload)) {
      amountBySlug[payload.slug] = payload.amount;
    }

    if (tonAmount !== 0n || (!isNftTransferPayload(payload) && isEmptyObject(amountBySlug))) {
      amountBySlug[TONCOIN.slug] = tonAmount;
    }

    return amountBySlug;
  }, [transaction]);

  const feeBySlug = useMemo(
    () => ({ [TONCOIN.slug]: transaction.networkFee }),
    [transaction.networkFee],
  );

  return (
    <>
      {isNftTransferPayload(transaction.payload) && <NftInfo nft={transaction.payload.nft} />}
      <p className={styles.label}>{lang('Receiving Address')}</p>
      <InteractiveTextField
        chain={TONCOIN.chain}
        address={transaction.displayedToAddress}
        isScam={transaction.isScam}
        className={buildClassName(styles.dataField, styles.receivingAddress)}
        copyNotification={lang('%chain% Address Copied', { chain: getChainTitle(TONCOIN.chain) }) as string}
      />
      {!isEmptyObject(amountBySlug) && (
        <DappAmountField
          label={isNftTransferPayload(transaction.payload) ? lang('Additional Amount Sent') : lang('Amount')}
          amountsBySlug={amountBySlug}
        />
      )}
      <DappAmountField label={lang('Fee')} amountsBySlug={feeBySlug} />
      <DappTransactionPayload transaction={transaction} tokensBySlug={tokensBySlug} />
    </>
  );
}
