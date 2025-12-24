import type { Wallet } from '@tonconnect/sdk';
import React, { memo, useEffect, useRef, useState } from '../../lib/teact/teact';

import type { TransferRow, ValidationError } from '../types';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import buildClassName from '../../util/buildClassName';
import { ANIMATED_STICKERS_PATHS } from '../../components/ui/helpers/animatedAssets';
import { downloadTemplate, MIXED_TRANSFERS_TEMPLATE } from '../utils/csvTemplates';
import { prettifyAddress } from '../utils/tonConnect';
import { validateAndProcessTransfer } from '../utils/transferValidation';

import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';
import Button from '../../components/ui/Button';

import styles from './DropPage.module.scss';

interface OwnProps {
  wallet?: Wallet;
  onConnectClick: NoneToVoidFunction;
  onDisconnectClick: NoneToVoidFunction;
  onAddTransferClick: NoneToVoidFunction;
  onSetCsvData: (data: TransferRow[]) => void;
  onNavigateToTransferList: () => void;
  isActive?: boolean;
}

function DropPage({
  wallet,
  onConnectClick,
  onDisconnectClick,
  onAddTransferClick,
  onSetCsvData,
  onNavigateToTransferList,
  isActive,
}: OwnProps) {
  const [isDropActive, setIsDropActive] = useState(false);
  const [validationError, setValidationError] = useState<ValidationError | undefined>();
  const [isValidatingCsv, setIsValidatingCsv] = useState(false);
  const [pendingFile, setPendingFile] = useState<File | undefined>();
  const [isCsvSampleVisible, setIsCsvSampleVisible] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>();

  const maxMessages = wallet?.device.features
    .find((f) => typeof f === 'object' && 'maxMessages' in f)?.maxMessages || 255;

  const { shouldRender: shouldRenderError, ref: errorRef } = useShowTransition({
    isOpen: Boolean(validationError),
    withShouldRender: true,
  });

  const { shouldRender: shouldRenderCsvSample, ref: csvSampleRef } = useShowTransition({
    isOpen: isCsvSampleVisible,
    withShouldRender: true,
  });

  const processCsvFile = useLastCallback((file: File) => {
    const reader = new FileReader();

    reader.onload = async (e) => {
      const content = e.target?.result as string;
      const rows = content.split(/\r?\n/).filter((line) => line.trim() !== '');

      if (rows.length > maxMessages) {
        setValidationError({
          line: maxMessages + 1,
          column: 0,
          reason: `CSV file exceeds the maximum of ${maxMessages} transfers`,
        });
        return;
      }

      setIsValidatingCsv(true);
      setValidationError(undefined);
      onSetCsvData([]);

      const parsedData: TransferRow[] = [];
      let error: ValidationError | undefined;

      for (let i = 0; i < rows.length; i++) {
        const line = rows[i].trim();
        const columns = line.split(',').map((col) => col.trim());

        if (columns.length < 3) {
          error = {
            line: i + 1,
            column: columns.length + 1,
            reason: 'Row must contain at least 3 columns: receiver, amount, and token type',
          };
          break;
        }

        const transfer = {
          receiver: columns[0],
          amount: columns[1],
          tokenIdentifier: columns[2],
          comment: columns[3] || '',
        };

        try {
          const validationResult = await validateAndProcessTransfer(transfer);

          if (!validationResult.isValid) {
            error = {
              line: i + 1,
              column: 1,
              reason: validationResult.error || 'Validation failed',
            };
            break;
          }

          if (validationResult.processedTransfer) {
            parsedData.push(validationResult.processedTransfer);
          }
        } catch (err) {
          error = {
            line: i + 1,
            column: 1,
            reason: err instanceof Error ? err.message : 'Processing failed',
          };
          break;
        }
      }

      setIsValidatingCsv(false);

      if (error) {
        setValidationError(error);
        onSetCsvData([]);
      } else {
        setValidationError(undefined);
        onSetCsvData(parsedData);
        if (wallet) {
          onNavigateToTransferList();
        } else {
          setPendingFile(file);
          onConnectClick();
        }
      }
    };

    reader.readAsText(file);
  });

  const handleDrop = useLastCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDropActive(false);

    const file = e.dataTransfer.files[0];
    if (file) {
      processCsvFile(file);
    }
  });

  const handleDragOver = useLastCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDropActive(true);
  });

  const handleDragLeave = useLastCallback(() => {
    setIsDropActive(false);
  });

  const handleFileChange = useLastCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      processCsvFile(e.target.files[0]);
    }
  });

  const handleButtonClick = useLastCallback(() => {
    if (!wallet) {
      onConnectClick();
      return;
    }
    if (fileInputRef.current) {
      fileInputRef.current.click();
    }
  });

  const handleAddTransfer = useLastCallback(() => {
    if (!wallet) {
      onConnectClick();
      return;
    }
    onAddTransferClick();
  });

  const handleDownloadTemplate = useLastCallback(() => {
    downloadTemplate(MIXED_TRANSFERS_TEMPLATE, 'mytonwallet_multi_transfer_template.csv');
  });

  const handleViewCsvSample = useLastCallback(() => {
    setIsCsvSampleVisible(true);
  });

  const handleCloseCsvSample = useLastCallback(() => {
    setIsCsvSampleVisible(false);
  });

  const handleCopyCsvSample = useLastCallback(async () => {
    try {
      await navigator?.clipboard?.writeText?.(MIXED_TRANSFERS_TEMPLATE);
      setIsCsvSampleVisible(false);
    } catch (err) {
      const textArea = document.createElement('textarea');
      textArea.value = MIXED_TRANSFERS_TEMPLATE;
      textArea.style.position = 'fixed';
      textArea.style.opacity = '0';
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand('copy');
        setIsCsvSampleVisible(false);
      } catch (fallbackErr) {
        console.error('Failed to copy:', fallbackErr);
      }
      document.body.removeChild(textArea);
    }
  });

  useEffect(() => {
    if (wallet && pendingFile) {
      const fileToProcess = pendingFile;
      setPendingFile(undefined);
      processCsvFile(fileToProcess);
    }
  }, [wallet, pendingFile, processCsvFile]);

  return (
    <div className={styles.container}>
      <div className={styles.content}>
        <div className={styles.root}>
          <div
            className={buildClassName(styles.importPanel, isDropActive && styles.dropActive)}
            onDrop={handleDrop}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
          >
            <AnimatedIconWithPreview
              play={isActive}
              tgsUrl={ANIMATED_STICKERS_PATHS.forge}
              previewUrl={ANIMATED_STICKERS_PATHS.forgePreview}
              size={ANIMATED_STICKER_BIG_SIZE_PX}
              className={styles.sticker}
              noLoop={false}
              nonInteractive
            />
            <p className={styles.title}>
              Send TON and tokens to multiple recipients in one batch operation
            </p>

            <div className={styles.importButtons}>
              <Button
                isSecondary
                onClick={handleAddTransfer}
                className={buildClassName(styles.importButton, styles.addButton)}
              >
                Add First Transfer
              </Button>
              <Button
                onClick={handleButtonClick}
                isLoading={isValidatingCsv}
                className={styles.importButton}
              >
                Upload CSV
              </Button>
              <Button
                onClick={handleDownloadTemplate}
                isSmall
                className={styles.importButton}
              >
                Download CSV Sample
              </Button>
              <Button
                onClick={handleViewCsvSample}
                isSmall
                className={styles.importButton}
              >
                View CSV Sample
              </Button>
            </div>
            <input
              type="file"
              ref={fileInputRef}
              accept=".csv"
              className={styles.hiddenInput}
              onChange={handleFileChange}
            />
          </div>

          {shouldRenderError && (
            <div ref={errorRef} className={styles.errorMessage}>
              An error occurred (line {validationError?.line},
              column {validationError?.column}). {validationError?.reason}
            </div>
          )}

          {shouldRenderCsvSample && (
            <div ref={csvSampleRef} className={styles.csvSampleOverlay} onClick={handleCloseCsvSample}>
              <div className={styles.csvSampleModal} onClick={(e) => e.stopPropagation()}>
                <div className={styles.csvSampleHeader}>
                  <h3 className={styles.csvSampleTitle}>CSV Sample</h3>
                  <div className={styles.csvSampleHeaderButtons}>
                    <Button
                      onClick={handleCopyCsvSample}
                      className={styles.csvSampleCopyButton}
                      isSmall
                    >
                      <i className="icon-copy" aria-hidden />
                    </Button>
                    <button className={styles.csvSampleClose} onClick={handleCloseCsvSample} title="Close">×</button>
                  </div>
                </div>
                <div className={styles.csvSampleContent}>
                  <pre className={styles.csvSampleText}>{MIXED_TRANSFERS_TEMPLATE}</pre>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
      <div className={styles.description}>
        {wallet ? (
          <>
            {!!maxMessages && (
              <p>
                The connected wallet supports up to <b>{maxMessages}</b> transfers.
                {!!maxMessages && maxMessages <= 4 && (
                  <>{' '}Use <b>W5</b> wallet to send up to <b>255</b> transfers.</>
                )}
              </p>
            )}
          </>
        ) : (
          <p>
            Connect <b>MyTonWallet</b> to access<br />the multi-send feature.
          </p>
        )}
      </div>
      {wallet ? (
        <div className={styles.walletInfo}>
          <div className={styles.walletAddress}>
            {wallet?.account ? prettifyAddress(wallet.account.address) : undefined}
          </div>
          <div className={styles.walletDescription}>
            Connected Wallet
            {' · '}
            <span className={styles.disconnectLink} onClick={onDisconnectClick}>
              Disconnect
            </span>
          </div>
        </div>
      ) : (
        <div className={styles.footer}>
          <Button
            isSimple
            className={styles.connectButton}
            onClick={onConnectClick}
          >
            Connect MyTonWallet
          </Button>
        </div>
      )}
    </div>
  );
}

export default memo(DropPage);
