import React, { memo } from '../../lib/teact/teact';

import type { ApiChain } from '../../api/types';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';
import Fee from '../ui/Fee';
import Modal from '../ui/Modal';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

interface OwnProps {
  isOpen: boolean;
  chain: ApiChain;
  /** The fee the emulated transactions actually consume */
  realFee: bigint;
  /** The part of the debited fee that the emulated transactions send back to the wallet */
  excess: bigint;
  onClose: NoneToVoidFunction;
}

function DappFeeDetailsModal({
  isOpen,
  chain,
  realFee,
  excess,
  onClose,
}: OwnProps) {
  const lang = useLang();
  const { nativeToken } = getChainConfig(chain);

  return (
    <Modal
      isOpen={isOpen}
      isCompact
      title={lang('App Fee Details')}
      onClose={onClose}
      onEnter={onClose}
    >
      <div className={styles.feeDetailsText}>
        {renderText(lang('$dapp_return_details', {
          fee_amount: <b><Fee terms={{ native: realFee + excess }} precision="exact" token={nativeToken} /></b>,
          received_amount: <b><Fee terms={{ native: excess }} precision="approximate" token={nativeToken} /></b>,
        }))}
      </div>
      <div className={buildClassName(styles.feeDetailsWarning, styles.warning)}>
        {lang('$dapp_return_disclaimer')}
      </div>
      <div className={modalStyles.buttons}>
        <Button isPrimary className={modalStyles.button} onClick={onClose}>{lang('Got It')}</Button>
      </div>
    </Modal>
  );
}

export default memo(DappFeeDetailsModal);
