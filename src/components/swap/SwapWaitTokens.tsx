import React, { memo, useMemo, useState } from '../../lib/teact/teact';

import type { ApiActivity, ApiSwapCexLabel } from '../../api/types';
import type { Account, UserSwapToken } from '../../global/types';

import { CEX_WAITING_DEADLINE } from '../../config';
import buildClassName from '../../util/buildClassName';
import { getChainTitle, getIsSupportedChain } from '../../util/chain';
import { formatCurrencyExtended } from '../../util/formatNumber';
import { getCexExternalExchangeId } from '../../util/swap/cex';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import { getIsInternalSwap } from '../../util/swap/getSwapType';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useQrCode from '../../hooks/useQrCode';

import CexSupportText from '../common/CexSupportText';
import Countdown from '../common/Countdown';
import SwapTokensInfo from '../common/SwapTokensInfo';
import Button from '../ui/Button';
import InteractiveTextField from '../ui/InteractiveTextField';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

const cexSupportClassNames = {
  description: styles.cexDescription,
  descriptionBold: styles.cexDescriptionBold,
  supportContact: styles.cexSupportContact,
};

interface OwnProps {
  isActive: boolean;
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
  amountIn?: string;
  amountOut?: string;
  payinAddress?: string;
  payoutAddress?: string;
  payinExtraId?: string;
  isManualDepositRequired?: boolean;
  cexLabel?: ApiSwapCexLabel;
  activity?: ApiActivity;
  accountChains?: Account['byChain'];
  onClose: NoneToVoidFunction;
}

function SwapWaitTokens({
  isActive,
  tokenIn,
  tokenOut,
  amountIn,
  amountOut,
  payinAddress,
  payoutAddress,
  payinExtraId,
  isManualDepositRequired,
  activity,
  accountChains,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const [isExpired, setIsExpired] = useState(false);

  const timestamp = useMemo(() => Date.now(), []);

  const { qrCodeRef, isInitialized } = useQrCode({
    address: payinAddress,
    isActive,
    hiddenClassName: styles.qrCodeHidden,
    hideLogo: true,
  });

  const shouldShowQrCode = !payinExtraId;
  const isInternalSwap = getIsInternalSwap({
    from: tokenIn, to: tokenOut, toAddress: payoutAddress, accountChains,
  });
  const shouldShowDepositInstructions = !isInternalSwap || isManualDepositRequired;
  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  const handleTimeout = useLastCallback(() => {
    setIsExpired(true);
  });

  function renderMemo() {
    if (!payinExtraId) return undefined;

    return (
      <div className={styles.textFieldWrapperFullWidth}>
        <span className={styles.textFieldLabel}>
          {lang('Memo')}
        </span>
        <InteractiveTextField
          address={payinExtraId}
          copyNotification={lang('Memo Copied')}
          noSavedAddress
          noExplorer
          className={styles.cexTextField}
        />
      </div>
    );
  }

  function renderInfo() {
    if (isExpired) {
      const cex = activity && 'cex' in activity ? activity.cex : undefined;
      const externalExchangeId = getCexExternalExchangeId(cex);

      return (
        <div className={styles.cexInfoBlock}>
          <span className={styles.cexImportantRed}>
            {lang('The time for sending coins is over.')}
          </span>
          <CexSupportText cex={cex} classNames={cexSupportClassNames} />
          {externalExchangeId && (
            <InteractiveTextField
              text={externalExchangeId}
              copyNotification={lang('External Exchange ID Copied')}
              noSavedAddress
              noExplorer
              className={styles.cexTextField}
            />
          )}
        </div>
      );
    }

    if (!shouldShowDepositInstructions) {
      return (
        <div className={styles.cexInfoBlock}>
          <span className={styles.cexDescription}>
            {lang('Please note that it may take up to a few hours for tokens to appear in your wallet.')}
          </span>
        </div>
      );
    }

    const chain = getIsSupportedChain(tokenIn?.chain) ? tokenIn.chain : undefined;

    return (
      <div className={styles.cexInfoBlock}>
        <span className={styles.cexDescription}>{lang('$swap_cex_to_wallet_description', {
          value: (
            <span className={styles.cexDescriptionBold}>
              {formatCurrencyExtended(Number(amountIn), tokenIn?.symbol ?? '', true)}
            </span>
          ),
          blockchain: (
            <span className={styles.cexDescriptionBold}>
              {getChainNetworkName(tokenIn?.chain)}
            </span>
          ),
          time: (
            <Countdown
              timestamp={timestamp}
              deadline={CEX_WAITING_DEADLINE}
              onCompleted={handleTimeout}
            />
          ),
        })}
        </span>
        <InteractiveTextField
          chain={chain}
          address={payinAddress}
          copyNotification={lang('%chain% Address Copied', { chain: chain ? getChainTitle(chain) : '' }) as string}
          noSavedAddress
          noExplorer
          noDimming
          className={styles.cexTextField}
        />
        {renderMemo()}
        {shouldShowQrCode && (
          <div className={buildClassName(styles.qrCode, !isInitialized && styles.qrCodeHidden)} ref={qrCodeRef} />
        )}
        <span className={styles.cexDescription}>
          {lang('Please note that it may take up to a few hours for tokens to appear in your wallet.')}
        </span>
      </div>
    );
  }

  return (
    <>
      <ModalHeader
        title={lang(isExpired ? 'Swap Expired' : (shouldShowDepositInstructions ? 'Waiting for Payment' : 'Swapping'))}
        onClose={onClose}
      />

      <div className={buildClassName(styles.scrollContent, styles.selectBlockchainBlock, 'custom-scroll')}>
        <SwapTokensInfo
          tokenIn={tokenIn}
          amountIn={amountIn}
          tokenOut={tokenOut}
          amountOut={amountOut}
        />

        <Transition
          name="fade"
          activeKey={isExpired ? 1 : 0}
        >
          {renderInfo()}
        </Transition>

        <div className={modalStyles.buttons}>
          <Button isPrimary onClick={onClose}>{lang('Close')}</Button>
        </div>
      </div>
    </>
  );
}

export default memo(SwapWaitTokens);
