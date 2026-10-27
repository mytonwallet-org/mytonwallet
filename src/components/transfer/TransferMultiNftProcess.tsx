import React, { memo } from '../../lib/teact/teact';

import type { ApiNft } from '../../api/types';

import {
  BURN_ADDRESS, BURN_CHUNK_DURATION_APPROX_SEC, NFT_BATCH_SIZE, NOTCOIN_EXCHANGERS,
} from '../../config';

import useLang from '../../hooks/useLang';

import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import Spinner from '../ui/Spinner';
import NftChips from './NftChips';
import NftInfo from './NftInfo';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Transfer.module.scss';

interface OwnProps {
  nfts: ApiNft[];
  sentNftsCount?: number;
  isPartial?: boolean;
  toAddress?: string;
  onClose: NoneToVoidFunction;
}

function TransferMultiNftProcess({
  nfts,
  sentNftsCount = 0,
  isPartial,
  toAddress,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const isInProgress = !isPartial && sentNftsCount < nfts.length;
  const isBurning = toAddress === BURN_ADDRESS;
  const isNotcoinBurning = toAddress === NOTCOIN_EXCHANGERS[0];

  const title = isPartial ? lang('Action Partially Completed') : isInProgress ? lang(
    `${(isBurning || isNotcoinBurning) ? 'Burning' : 'Sending'}: %n% of %m% NFTs...`,
    { n: sentNftsCount, m: nfts.length },
  ) : lang('Sent');
  const duration = (Math.ceil(nfts.length / NFT_BATCH_SIZE) * BURN_CHUNK_DURATION_APPROX_SEC) / 60;

  return (
    <>
      <ModalHeader title={title} />

      <div className={modalStyles.transitionContent}>
        {isPartial && (
          <div className={styles.infoBox}>
            {lang('$action_partially_completed_description', { completed: sentNftsCount, total: nfts.length })}
          </div>
        )}
        {isInProgress && (
          <>
            <Spinner className={styles.spinner} />
            <div className={styles.infoBox}>{lang('$multi_send_nft_warning', { duration })}</div>
          </>
        )}
        {nfts.length === 1 ? <NftInfo nft={nfts[0]} /> : <NftChips nfts={nfts} />}
        {!isInProgress && (
          <div className={modalStyles.buttons}>
            <Button onClick={onClose} isPrimary>{lang('Close')}</Button>
          </div>
        )}
      </div>
    </>
  );
}

export default memo(TransferMultiNftProcess);
