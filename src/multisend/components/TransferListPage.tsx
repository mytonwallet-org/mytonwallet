import { beginCell } from '@ton/core';
import React, { memo, useState } from '../../lib/teact/teact';

import type { TransferRow } from '../types';

import { TONCOIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { formatNumber } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';
import { setEnvironment } from '../../api/environment';
import { createJettonTransferPayload, getJettonWalletAddress } from '../utils/tokens';
import { sendTransaction, tonConnect } from '../utils/tonConnect';
import { isNativeTokenIdentifier } from '../utils/transferValidation';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import Button from '../../components/ui/Button';

import styles from './TransferListPage.module.scss';

interface OwnProps {
  isActive?: boolean;
  transferData: TransferRow[];
  onSetTransferData: (data: TransferRow[]) => void;
  onAddTransferClick: () => void;
  onEditTransferClick: (transfer: TransferRow, index: number) => void;
  onBack: () => void;
}

setEnvironment({});

const COMMENT_OPCODE = 0;
const MIN_TON_FOR_JETTON = 0.05;

function TransferListPage({
  isActive,
  transferData,
  onSetTransferData,
  onAddTransferClick,
  onEditTransferClick,
  onBack,
}: OwnProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [isResolvingAddresses, setIsResolvingAddresses] = useState(false);
  const [txResult, setTxResult] = useState<{ success: number; failed: number } | undefined>();

  const { shouldRender: shouldRenderTxResult, ref: txResultRef } = useShowTransition({
    isOpen: Boolean(txResult),
    withShouldRender: true,
  });

  useHistoryBack({
    isActive,
    onBack,
  });

  const handleCancel = useLastCallback(() => {
    onSetTransferData([]);
    setTxResult(undefined);
    onBack();
  });

  const handleSendAll = useLastCallback(async () => {
    if (!transferData.length) return;

    const senderAddress = tonConnect.wallet?.account.address;
    if (!senderAddress) {
      setTxResult({
        success: 0,
        failed: transferData.length,
      });
      return;
    }

    setIsLoading(true);
    setIsResolvingAddresses(true);
    setTxResult(undefined);

    try {
      const tonTransfers: any[] = [];
      const jettonTransfers: any[] = [];

      for (const row of transferData) {
        const {
          receiver,
          amount,
          tokenIdentifier,
          comment,
          resolvedTokenInfo,
          resolvedAddress,
        } = row;
        const targetAddress = resolvedAddress || receiver;

        if (isNativeTokenIdentifier(tokenIdentifier)) {
          const amountNano = Math.floor(Number(amount) * 1e9).toString();
          const payload = comment ? createCommentPayload(comment) : undefined;

          tonTransfers.push({
            address: targetAddress,
            amount: amountNano,
            payload,
          });
        } else {
          const tokenInfo = resolvedTokenInfo;
          if (!tokenInfo) continue;

          const minterAddress = tokenInfo.tokenAddress;
          const decimals = tokenInfo.decimals;
          const tokenAmount = BigInt(Math.floor(Number(amount) * 10 ** decimals));

          try {
            const senderJettonWalletAddress = await getJettonWalletAddress(senderAddress, minterAddress);

            const payload = createJettonTransferPayload(
              senderAddress,
              targetAddress,
              tokenAmount,
              comment,
            );

            jettonTransfers.push({
              address: senderJettonWalletAddress.toString(),
              amount: (MIN_TON_FOR_JETTON * 1e9).toString(),
              payload,
            });
          } catch (error) {
            // eslint-disable-next-line no-console
            console.error(
              `Failed to create jetton transfer for ${tokenIdentifier} to ${targetAddress}:`,
              error,
            );
          }
        }
      }

      setIsResolvingAddresses(false);

      const allTransfers = [
        ...tonTransfers,
        ...jettonTransfers,
      ];

      await sendTransaction({
        validUntil: Math.floor(Date.now() / 1000) + 360,
        messages: allTransfers,
      });

      setTxResult({
        success: allTransfers.length,
        failed: 0,
      });
    } catch (error) {
      setIsResolvingAddresses(false);

      // eslint-disable-next-line no-console
      console.error('Transaction failed:', error);

      setTxResult({
        success: 0,
        failed: transferData.length,
      });
    } finally {
      setIsLoading(false);
    }
  });

  const handleTransferClick = useLastCallback((transfer: TransferRow, index: number) => {
    if (onEditTransferClick) {
      onEditTransferClick(transfer, index);
    }
  });

  const handleAddTransfer = useLastCallback(() => {
    if (onAddTransferClick) {
      onAddTransferClick();
    }
  });

  return (
    <div className={styles.root}>
      <div className={styles.transferPreview}>
        <div className={styles.addButtonContainer}>
          <Button
            isSecondary
            isSmall
            className={styles.addButton}
            onClick={handleAddTransfer}
          >
            Add Transfer
          </Button>
        </div>

        <div className={styles.transfersHeader}>
          <div className={styles.blockTitle}>
            {transferData.length} transfer{transferData.length !== 1 ? 's' : ''}
          </div>
        </div>

        <div className={styles.transfersList}>
          {transferData.map((row, index) => {
            const isNative = isNativeTokenIdentifier(row.tokenIdentifier);
            const tokenInfo = !isNative ? row.resolvedTokenInfo : undefined;
            const displayToken = isNative ? TONCOIN.symbol : (tokenInfo?.symbol ?? row.tokenIdentifier);
            const displayAddress = row.receiver;
            const addressTitle = row.resolvedAddress
              ? `${row.receiver} → ${row.resolvedAddress}`
              : row.receiver;

            return (
              <div
                key={index}
                className={styles.transferItem}
                title={addressTitle}
                onClick={() => handleTransferClick(row, index)}
              >
                <div className={styles.transferContent}>
                  {formatNumber(row.amount)} {displayToken}{' '}
                  <span className={styles.toAddress}>
                    to {shortenAddress(displayAddress, 4)}
                  </span>
                </div>

                <div className={styles.transferActions}>
                  {row.comment !== 'undefined' && row.comment && (
                    <i
                      className={buildClassName(styles.iconComment, 'icon-paste')}
                      aria-hidden
                      title={row.comment}
                    />
                  )}
                  <i
                    className={buildClassName(styles.iconChevronRight, 'icon-chevron-right')}
                    aria-hidden
                  />
                </div>
              </div>
            );
          })}
        </div>

        {shouldRenderTxResult && txResult && (
          <div
            className={buildClassName(
              styles.txResult,
              txResult.failed > 0 ? styles.error : styles.success,
            )}
            ref={txResultRef}
          >
            {txResult.success} transfers succeeded, {txResult.failed} failed
          </div>
        )}

        <div className={styles.actionButtons}>
          <Button onClick={handleCancel}>
            Cancel
          </Button>
          <Button
            isPrimary
            isLoading={isLoading || isResolvingAddresses}
            onClick={handleSendAll}
          >
            {isResolvingAddresses ? 'Resolving Addresses...' : 'Send All'}
          </Button>
        </div>
      </div>
    </div>
  );
}

export default memo(TransferListPage);

function createCommentPayload(comment: string): string {
  const cell = beginCell()
    .storeUint(COMMENT_OPCODE, 32)
    .storeBuffer(Buffer.from(comment))
    .endCell();

  return cell.toBoc().toString('base64');
}
