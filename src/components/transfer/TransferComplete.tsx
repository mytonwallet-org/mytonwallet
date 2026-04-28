import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiNft } from '../../api/types';

import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TransferResult from '../common/TransferResult';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';
import NftChips from './NftChips';
import NftInfo from './NftInfo';

import styles from '../common/TransferResult.module.scss';
import modalStyles from '../ui/Modal.module.scss';

interface OwnProps {
  isActive: boolean;
  amount?: bigint;
  symbol: string;
  txId?: string;
  tokenSlug: string;
  toAddress?: string;
  comment?: string;
  decimals?: number;
  nfts?: ApiNft[];
  onInfoClick: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

function TransferComplete({
  isActive,
  amount,
  symbol,
  txId,
  tokenSlug,
  toAddress,
  comment,
  decimals,
  nfts,
  onInfoClick,
  onClose,
}: OwnProps) {
  const { startTransfer } = getActions();

  const lang = useLang();
  const isNftTransfer = Boolean(nfts?.length);

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  useEffect(() => {
    return isActive
      ? captureKeyboardListeners({ onEnter: onClose })
      : undefined;
  }, [isActive, onClose]);

  const handleTransactionRepeatClick = useLastCallback(() => {
    startTransfer({
      tokenSlug,
      toAddress,
      amount,
      comment,
    });
  });

  return (
    <>
      <ModalHeader title={lang(isNftTransfer ? 'NFT has been sent!' : 'Coins have been sent!')} onClose={onClose} />

      <div className={modalStyles.transitionContent}>
        {isNftTransfer ? (
          <>
            <AnimatedIconWithPreview
              play={isActive}
              noLoop={false}
              nonInteractive
              className={styles.sticker}
              tgsUrl={ANIMATED_STICKERS_PATHS.thumbUp}
              previewUrl={ANIMATED_STICKERS_PATHS.thumbUpPreview}
            />
            {nfts.length === 1 ? <NftInfo nft={nfts[0]} /> : <NftChips nfts={nfts} />}
            {Boolean(txId) && (
              <div className={buildClassName(styles.buttons, styles.buttonsAfterNft)}>
                <Button className={styles.button} onClick={onInfoClick}>{lang('Details')}</Button>
              </div>
            )}
          </>
        ) : (
          <TransferResult
            playAnimation={isActive}
            amount={amount ? -amount : undefined}
            tokenSymbol={symbol}
            firstButtonText={txId ? lang('Details') : undefined}
            secondButtonText={lang('Repeat')}
            onFirstButtonClick={onInfoClick}
            onSecondButtonClick={handleTransactionRepeatClick}
            decimals={decimals}
          />
        )}

        <div className={modalStyles.buttons}>
          <Button onClick={onClose} isPrimary>{lang('Close')}</Button>
        </div>
      </div>
    </>
  );
}

export default memo(TransferComplete);
