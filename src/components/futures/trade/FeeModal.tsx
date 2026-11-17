import React, { memo } from '../../../lib/teact/teact';

import type { ApiPerpsQuote } from '../../../api/types';

import { formatPerpsFeeEstimate, formatPerpsNetworkFee } from '../helpers/formatPerps';
import { buildPerpsFeeLines } from '../helpers/perpsFees';

import useLang from '../../../hooks/useLang';

import Button from '../../ui/Button';
import Modal from '../../ui/Modal';
import DetailRow from '../DetailRow';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  quote: ApiPerpsQuote;
  onClose: NoneToVoidFunction;
}

function FeeModal({ isOpen, quote, onClose }: OwnProps) {
  const lang = useLang();

  const { estimatedFees } = quote;
  const lines = estimatedFees
    ? buildPerpsFeeLines(lang, estimatedFees, formatPerpsFeeEstimate, { isFromBalance: quote.funding === 'balance' })
    : [];
  // The USDC total leaves out the Arbitrum gas of the deposit, so the gas is listed after it
  const networkFee = formatPerpsNetworkFee(quote);
  if (networkFee !== undefined) lines.push({ label: lang('Network Fee'), value: networkFee });

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={lang('Fee')}
      contentClassName={styles.feeModalContent}
      onClose={onClose}
    >
      {Boolean(lines.length) && (
        <div className={styles.card}>
          {lines.map(({ label, value }) => <DetailRow key={label} label={label} value={value} />)}
        </div>
      )}
      {!estimatedFees && <p className={styles.cardNote}>{lang('PerpsFeesAtExecution')}</p>}
      <p className={styles.cardNote}>{lang('PerpsFeeEstimateHint')}</p>
      <div className={modalStyles.buttons}>
        <Button isPrimary className={modalStyles.button} onClick={onClose}>{lang('Got It')}</Button>
      </div>
    </Modal>
  );
}

export default memo(FeeModal);
