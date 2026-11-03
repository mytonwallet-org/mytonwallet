import React, { memo, useEffect, useMemo, useRef } from '../../lib/teact/teact';

import type { ApiDappTransfer, ApiParsedStateInit, ApiToken } from '../../api/types';
import type { LangFn } from '../../hooks/useLang';

import { TONCOIN } from '../../config';
import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { getChainTitle } from '../../util/chain';
import isEmptyObject from '../../util/isEmptyObject';
import {
  getPayloadRecipientAddress,
  isNftTransferPayload,
  isTokenTransferPayload,
} from '../../util/ton/transfer';

import useFlag from '../../hooks/useFlag';
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
  const payloadRecipientAddress = getPayloadRecipientAddress(transaction);

  return (
    <>
      {transaction.isDangerous ? (
        <div className={buildClassName(styles.transferWarning, styles.warning)}>
          {renderText(lang('$hardware_payload_warning'))}
        </div>
      ) : transaction.stateInit && (
        <div className={buildClassName(styles.transferWarning, styles.warning)}>
          {renderText(lang('$signature_warning'))}
        </div>
      )}
      {isNftTransferPayload(transaction.payload) && <NftInfo nft={transaction.payload.nft} />}
      <p className={styles.label}>{lang(payloadRecipientAddress ? 'Contract Address' : 'Receiving Address')}</p>
      <InteractiveTextField
        chain={TONCOIN.chain}
        address={transaction.toAddress}
        isScam={transaction.isScam}
        className={buildClassName(styles.dataField, styles.receivingAddress)}
        copyNotification={lang('%chain% Address Copied', { chain: getChainTitle(TONCOIN.chain) }) as string}
      />
      {payloadRecipientAddress && (
        <>
          <p className={styles.label}>{lang('Recipient Address')}</p>
          <InteractiveTextField
            chain={TONCOIN.chain}
            address={payloadRecipientAddress}
            className={buildClassName(styles.dataField, styles.receivingAddress)}
            copyNotification={lang('%chain% Address Copied', { chain: getChainTitle(TONCOIN.chain) }) as string}
          />
        </>
      )}
      {!isEmptyObject(amountBySlug) && (
        <DappAmountField
          label={isNftTransferPayload(transaction.payload) ? lang('Additional Amount Sent') : lang('Amount')}
          amountsBySlug={amountBySlug}
        />
      )}
      <DappAmountField label={lang('Fee')} amountsBySlug={feeBySlug} />
      <DappTransactionPayload transaction={transaction} tokensBySlug={tokensBySlug} />
      {transaction.stateInit && (
        <DappTransactionStateInit stateInit={transaction.stateInit} parsedStateInit={transaction.parsedStateInit} />
      )}
    </>
  );
}

function DappTransactionStateInit({ stateInit, parsedStateInit }: {
  stateInit: string;
  parsedStateInit?: ApiParsedStateInit;
}) {
  const lang = useLang();
  const stateInitRef = useRef<HTMLDivElement>();
  const [isExpanded, expand] = useFlag(false);

  useEffect(() => {
    const stateInitElement = stateInitRef.current;
    if (stateInitElement && stateInitElement.scrollWidth <= stateInitElement.clientWidth) {
      expand();
    }
  }, [expand]);

  return (
    <>
      <p className={styles.label}>{lang('Contract Initialization Data')}</p>
      {parsedStateInit && (
        <div className={buildClassName(styles.payloadField, styles.payloadField_text, styles.stateInitSummary)}>
          {getStateInitSummary(lang, parsedStateInit)}
        </div>
      )}
      {isExpanded ? (
        <InteractiveTextField
          text={stateInit}
          copyNotification={lang('Contract Initialization Data Copied')}
          className={styles.dataField}
        />
      ) : (
        <div ref={stateInitRef} className={styles.payloadField}>
          {stateInit}
          <button type="button" className={styles.payloadFieldExpand} onClick={expand}>
            {lang('View')}
          </button>
        </div>
      )}
    </>
  );
}

function getStateInitSummary(lang: LangFn, { walletName, isDeployable }: ApiParsedStateInit) {
  if (!isDeployable) return lang('$state_init_not_deployable');

  return walletName
    ? lang('$state_init_deploys_wallet', { version: walletName })
    : lang('$state_init_deploys_contract');
}
