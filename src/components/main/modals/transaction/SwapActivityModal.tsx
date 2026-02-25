import React, { memo, useEffect, useMemo } from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type { ApiChain, ApiSwapActivity, ApiSwapAsset, ApiTokenWithPrice } from '../../../../api/types';
import type { Account, Theme } from '../../../../global/types';
import { SwapType } from '../../../../global/types';

import {
  ANIMATED_STICKER_TINY_ICON_PX,
  ANIMATION_END_DELAY,
  ANIMATION_LEVEL_MIN,
  CHANGELLY_LIVE_CHAT_URL,
  CHANGELLY_SECURITY_EMAIL,
  CHANGELLY_SUPPORT_EMAIL,
  CHANGELLY_WAITING_DEADLINE,
} from '../../../../config';
import { Big } from '../../../../lib/big.js';
import { resolveSwapAsset } from '../../../../global/helpers';
import {
  selectCurrentAccount,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import { getIsActivityPendingForUser, getShouldSkipSwapWaitingStatus, parseTxId } from '../../../../util/activities';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle, getIsSupportedChain } from '../../../../util/chain';
import { formatFullDay, formatTime } from '../../../../util/dateFormat';
import { formatCurrencyExtended } from '../../../../util/formatNumber';
import { shareUrl } from '../../../../util/share';
import getChainNetworkName from '../../../../util/swap/getChainNetworkName';
import { getIsInternalSwap, getSwapType } from '../../../../util/swap/getSwapType';
import { getChainBySlug, getIsNativeToken } from '../../../../util/tokens';
import { getExplorerTransactionUrl, getViewTransactionUrl } from '../../../../util/url';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import usePrevDuringAnimation from '../../../../hooks/usePrevDuringAnimation';
import useQrCode from '../../../../hooks/useQrCode';

import Countdown from '../../../common/Countdown';
import SwapTokensInfo from '../../../common/SwapTokensInfo';
import TransactionFee from '../../../common/TransactionFee';
import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';
import InteractiveTextField from '../../../ui/InteractiveTextField';
import Modal, { CLOSE_DURATION, CLOSE_DURATION_PORTRAIT } from '../../../ui/Modal';
import ModalHeader from '../../../ui/ModalHeader';

import modalStyles from '../../../ui/Modal.module.scss';
import styles from './TransactionModal.module.scss';

type StateProps = {
  accountChains?: Account['byChain'];
  activity?: ApiSwapActivity;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  tokensBySlug?: Record<string, ApiTokenWithPrice>;
  theme: Theme;
  isSwapDisabled?: boolean;
  isSensitiveDataHidden?: true;
  isTestnet?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
};

const CHANGELLY_EXPIRE_CHECK_STATUSES = new Set(['new', 'waiting']);
const CHANGELLY_PENDING_STATUSES = new Set(['new', 'waiting', 'confirming', 'exchanging', 'sending']);
const CHANGELLY_ERROR_STATUSES = new Set(['failed', 'expired', 'refunded', 'overdue']);
const ONCHAIN_ERROR_STATUSES = new Set(['failed', 'expired']);

function SwapActivityModal({
  activity,
  tokensBySlug,
  swapTokensBySlug,
  theme,
  accountChains,
  isSwapDisabled,
  isSensitiveDataHidden,
  isTestnet,
  selectedExplorerIds,
}: StateProps) {
  const {
    fetchActivityDetails,
    startSwap,
    closeActivityInfo,
    selectToken,
    openTransactionInfo,
  } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const isOpen = Boolean(activity);
  const animationLevel = getGlobal().settings.animationLevel;
  const animationDuration = animationLevel === ANIMATION_LEVEL_MIN
    ? 0
    : (isPortrait ? CLOSE_DURATION_PORTRAIT : CLOSE_DURATION) + ANIMATION_END_DELAY;
  const renderedActivity = usePrevDuringAnimation(activity, animationDuration);
  const appTheme = useAppTheme(theme);

  const {
    id,
    timestamp,
    networkFee = '0',
    ourFee = '0',
    shouldLoadDetails,
    extra,
  } = renderedActivity ?? {};
  const { payinAddress, payoutAddress, payinExtraId } = renderedActivity?.cex || {};
  const isAggregatedSwap = Boolean(extra?.mtwAggregator);

  let fromAmount = '0';
  let toAmount = '0';
  let isPending = true;
  let isError = false;
  let shouldRenderCexInfo = false;
  let isCexError = false;
  let isCexHold = false;
  let isCexWaiting = false;
  let isCexPending = false;
  let isExpired = false;
  let cexTransactionId = '';
  let title = '';
  let titleBadge: string | undefined;
  let isTitleBadgeWarning = false;
  let cexErrorMessage = '';
  let isCountdownFinished = false;

  const fromToken = useMemo(() => {
    if (!renderedActivity?.from || !swapTokensBySlug || !tokensBySlug) return undefined;

    const prioritySwapToken = resolveSwapAsset(swapTokensBySlug, renderedActivity.from);
    if (!prioritySwapToken) {
      return resolveSwapAsset(tokensBySlug, renderedActivity.from);
    }

    return prioritySwapToken;
  }, [renderedActivity?.from, swapTokensBySlug, tokensBySlug]);

  const toToken = useMemo(() => {
    if (!renderedActivity?.to || !swapTokensBySlug || !tokensBySlug) return undefined;

    const prioritySwapToken = resolveSwapAsset(swapTokensBySlug, renderedActivity.to);
    if (!prioritySwapToken) {
      return resolveSwapAsset(tokensBySlug, renderedActivity.to);
    }

    return prioritySwapToken;
  }, [renderedActivity?.to, swapTokensBySlug, tokensBySlug]);

  const isInternalSwap = getIsInternalSwap({
    from: fromToken, to: toToken, toAddress: payoutAddress, accountChains,
  });

  if (renderedActivity) {
    const { status, cex } = renderedActivity;
    fromAmount = renderedActivity.fromAmount;
    toAmount = renderedActivity.toAmount;

    if (cex) {
      isCountdownFinished = timestamp
        ? (timestamp + CHANGELLY_WAITING_DEADLINE - Date.now() < 0)
        : false;
      isExpired = CHANGELLY_EXPIRE_CHECK_STATUSES.has(cex.status) && isCountdownFinished;
      shouldRenderCexInfo = cex.status !== 'finished';
      isPending = !isExpired && CHANGELLY_PENDING_STATUSES.has(cex.status);
      isCexPending = isPending;
      isCexError = isExpired || CHANGELLY_ERROR_STATUSES.has(cex.status);
      isCexHold = cex.status === 'hold';
      isCexWaiting = cex.status === 'waiting'
        && !isExpired && !getShouldSkipSwapWaitingStatus(renderedActivity, accountChains ?? {});
      cexTransactionId = cex.transactionId;
    } else {
      isPending = getIsActivityPendingForUser(renderedActivity);
      isError = ONCHAIN_ERROR_STATUSES.has(status);
    }

    if (isPending) {
      title = lang('Swapping');
    } else if (isCexHold) {
      title = lang('$swap_action');
      titleBadge = lang('On Hold');
      isTitleBadgeWarning = true;
    } else if (isCexError) {
      const { status: cexStatus } = renderedActivity.cex ?? {};
      if (cexStatus === 'expired' || cexStatus === 'overdue') {
        title = lang('$swap_action');
        titleBadge = lang('Expired');
        cexErrorMessage = lang('You have not sent the coins to the specified address.');
      } else if (cexStatus === 'refunded') {
        title = lang('$swap_action');
        titleBadge = lang('Refunded');
        cexErrorMessage = lang('Exchange failed and coins were refunded to your wallet.');
      } else {
        title = lang('$swap_action');
        titleBadge = lang('Failed');
      }
    } else if (isError) {
      title = lang('$swap_action');
      titleBadge = lang('Failed');
    } else {
      title = lang('Swapped');
    }
  }

  const handleClose = useLastCallback(() => {
    closeActivityInfo({ id: id! });
  });

  const handleSwapClick = useLastCallback(() => {
    closeActivityInfo({ id: id! });
    startSwap({
      tokenInSlug: fromToken!.slug,
      tokenOutSlug: toToken!.slug,
      amountIn: fromAmount,
    });
  });

  const handleTokenClick = useLastCallback((tokenSlug: string) => {
    closeActivityInfo({ id: id! });
    selectToken({ slug: tokenSlug });
  });

  const swapTransactionInfo = renderedActivity ? getTransactionHash(renderedActivity) : undefined;
  const swapChain = swapTransactionInfo?.chain && getIsSupportedChain(swapTransactionInfo.chain)
    ? swapTransactionInfo.chain
    : undefined;

  const handleShareClick = useLastCallback(() => {
    const url = getViewTransactionUrl(swapChain!, swapTransactionInfo!.hash, isTestnet);
    void shareUrl(url);
  });

  const handleViewDetails = useLastCallback(() => {
    if (!renderedActivity) return;

    const traceId = parseTxId(renderedActivity.id).hash;
    const chain = getChainBySlug(renderedActivity.from);

    if (!traceId || !chain) {
      return;
    }

    openTransactionInfo({ txId: traceId, chain });
  });

  useEffect(() => {
    if (id && shouldLoadDetails) fetchActivityDetails({ id });
  }, [id, shouldLoadDetails]);

  const modalTitle = useMemo(() => (
    <div className={styles.transactionHeader}>
      <div className={styles.headerTitle}>
        {title}
        {isPending && (
          <AnimatedIconWithPreview
            play={isOpen}
            size={ANIMATED_STICKER_TINY_ICON_PX}
            nonInteractive
            noLoop={false}
            tgsUrl={ANIMATED_STICKERS_PATHS[appTheme].iconClock}
            previewUrl={ANIMATED_STICKERS_PATHS[appTheme].preview.iconClock}
          />
        )}
        {!!titleBadge && (
          <span className={buildClassName(styles.headerTitle__badge, isTitleBadgeWarning && styles.warning)}>
            {titleBadge}
          </span>
        )}
      </div>
      {!!timestamp && (
        <div className={styles.headerDate}>
          {formatFullDay(lang.code!, timestamp)}, {formatTime(timestamp)}
        </div>
      )}
    </div>
  ), [appTheme, isOpen, isPending, isTitleBadgeWarning, lang.code, timestamp, title, titleBadge]);

  function renderFooterButton() {
    let isButtonVisible = true;
    let buttonText = 'Swap Again';

    if (isCexWaiting) {
      return (
        <Button onClick={handleClose} className={buildClassName(styles.button, styles.swapFooterButton)}>
          {lang('Close')}
        </Button>
      );
    }

    if (isCexHold) {
      isButtonVisible = false;
    } else if (isCexError) {
      const { status: cexStatus } = renderedActivity?.cex ?? {};
      if (cexStatus === 'expired' || cexStatus === 'refunded' || cexStatus === 'overdue') {
        buttonText = 'Try Again';
      }
    }

    if (!isButtonVisible) {
      return undefined;
    }

    return (
      <Button onClick={handleSwapClick} className={buildClassName(styles.button, styles.swapFooterButton)}>
        {lang(buttonText)}
      </Button>
    );
  }

  function renderCexInformation() {
    if (isCexHold) {
      return (
        <div className={styles.textFieldWrapper}>
          <span className={styles.changellyDescription}>
            {lang('$swap_changelly_kyc_security', {
              email: (
                <span className={styles.changellyDescriptionBold}>
                  {CHANGELLY_SECURITY_EMAIL}
                </span>
              ),
            })}
          </span>
          {cexTransactionId && (
            <InteractiveTextField
              text={cexTransactionId}
              copyNotification={lang('Transaction ID Copied')}
              noSavedAddress
              noExplorer
            />
          )}
        </div>
      );
    }

    return (
      <div className={buildClassName(styles.textFieldWrapper, styles.swapSupportBlock)}>
        {cexErrorMessage && <span className={styles.errorCexMessage}>{cexErrorMessage}</span>}

        {isCexPending && (
          <span className={buildClassName(styles.changellyDescription)}>
            {lang('Please note that it may take up to a few hours for tokens to appear in your wallet.')}
          </span>
        )}
        {isCountdownFinished && (
          <>
            <span className={styles.changellyDescription}>
              {lang('$swap_changelly_support', {
                livechat: (
                  <a
                    href={CHANGELLY_LIVE_CHAT_URL}
                    target="_blank"
                    rel="noreferrer"
                    className={styles.changellyDescriptionBold}
                  >
                    {lang('Changelly Live Chat')}
                  </a>
                ),
                email: (
                  <span className={styles.changellyDescriptionBold}>
                    {CHANGELLY_SUPPORT_EMAIL}
                  </span>
                ),
              })}
            </span>
            {cexTransactionId && (
              <InteractiveTextField
                text={cexTransactionId}
                copyNotification={lang('Transaction ID Copied')}
                noSavedAddress
                noExplorer
              />
            )}
          </>
        )}
      </div>
    );
  }

  function renderMemo() {
    if (!payinExtraId) return undefined;

    return (
      <div className={styles.textFieldWrapper}>
        <span className={styles.textFieldLabel}>
          {lang('Memo')}
        </span>
        <InteractiveTextField
          address={payinExtraId}
          copyNotification={lang('Memo Copied')}
          noSavedAddress
          noExplorer
        />
      </div>
    );
  }

  function renderTransactionId() {
    const transactionHash = renderedActivity && getTransactionHash(renderedActivity);
    if (!transactionHash) return undefined;
    const { hash, chain } = transactionHash;
    const transactionUrl = getExplorerTransactionUrl(chain, hash, isTestnet, selectedExplorerIds?.[chain]);

    return (
      <div className={styles.textFieldWrapper}>
        <span className={styles.textFieldLabel}>
          {lang('Transaction ID')}
        </span>
        <InteractiveTextField
          noSavedAddress
          address={hash}
          addressUrl={transactionUrl}
          chain={chain}
          isTransaction
          copyNotification={lang('Transaction ID Copied')}
        />
      </div>
    );
  }

  function renderFee() {
    if (!(Number(networkFee) || shouldLoadDetails) || !fromToken) {
      return undefined;
    }

    const terms = getIsNativeToken(renderedActivity?.from) ? {
      native: Big(networkFee).add(ourFee).toString(),
    } : {
      native: networkFee,
      token: ourFee,
    };

    return (
      <TransactionFee
        terms={terms}
        token={fromToken}
        precision={isPending ? 'approximate' : 'exact'}
        isLoading={shouldLoadDetails}
      />
    );
  }

  function renderAddress() {
    const isToWallet = renderedActivity
      && getSwapType(renderedActivity.from, renderedActivity.to, accountChains ?? {}) === SwapType.CrosschainToWallet;
    const address = isToWallet ? payinAddress : payoutAddress;
    const token = isToWallet ? fromToken : toToken;
    const chain = getIsSupportedChain(token?.chain) ? token.chain : undefined;

    if (!address) {
      return undefined;
    }

    return (
      <div className={styles.textFieldWrapper}>
        <span className={styles.textFieldLabel}>
          {lang(isToWallet ? 'Address for %blockchain% transfer' : 'Your %blockchain% Address', {
            blockchain: token?.name,
          })}
        </span>
        <InteractiveTextField
          chain={chain}
          address={address}
          copyNotification={lang('%chain% Address Copied', { chain: chain ? getChainTitle(chain) : '' }) as string}
          noSavedAddress
          noExplorer
          noDimming
        />
      </div>
    );
  }

  function renderSwapInfo() {
    if (isCexWaiting) {
      const chain = getIsSupportedChain(fromToken?.chain) ? fromToken.chain : undefined;

      return (
        <div className={styles.changellyInfoBlock}>
          {renderFee()}
          <span className={styles.changellyDescription}>{lang('$swap_changelly_to_wallet_description1', {
            value: (
              <span className={styles.changellyDescriptionBold}>
                {formatCurrencyExtended(Number(fromAmount), fromToken?.symbol ?? '', true)}
              </span>
            ),
            blockchain: (
              <span className={styles.changellyDescriptionBold}>
                {getChainNetworkName(fromToken?.chain)}
              </span>
            ),
            time: <Countdown timestamp={timestamp ?? 0} deadline={CHANGELLY_WAITING_DEADLINE} />,
          })}
          </span>
          <InteractiveTextField
            chain={chain}
            address={payinAddress}
            copyNotification={lang('%chain% Address Copied', { chain: chain ? getChainTitle(chain) : '' }) as string}
            noSavedAddress
            noExplorer
            noDimming
          />
          {renderMemo()}
          {payinAddress && !payinExtraId && <AddressQr isActive={isOpen} address={payinAddress} />}
        </div>
      );
    }

    return (
      <>
        {renderFee()}
        {!isInternalSwap && renderAddress()}
        {!isInternalSwap && renderMemo()}
      </>
    );
  }

  function renderContent() {
    const footerButton = !isSwapDisabled ? renderFooterButton() : undefined;

    const viewDetailsButton = isAggregatedSwap ? (
      <Button onClick={handleViewDetails} className={buildClassName(styles.button, styles.swapFooterButton)}>
        {lang('View details')}
      </Button>
    ) : undefined;

    const shouldRenderFooter = footerButton || viewDetailsButton;
    const shouldUseGridFooter = Boolean(footerButton && viewDetailsButton);

    return (
      <div className={modalStyles.transitionContent}>
        <SwapTokensInfo
          isSensitiveDataHidden={isSensitiveDataHidden}
          tokenIn={fromToken}
          amountIn={fromAmount}
          tokenOut={toToken}
          amountOut={toAmount}
          isError={isError || isCexError}
          onTokenClick={handleTokenClick}
        />
        <div className={styles.infoBlock}>
          {renderSwapInfo()}
          {shouldRenderCexInfo && renderCexInformation()}
          {renderTransactionId()}
        </div>
        {shouldRenderFooter && (
          <div className={buildClassName(styles.footer, shouldUseGridFooter && styles.swapFooter)}>
            {viewDetailsButton}
            {footerButton}
          </div>
        )}
      </div>
    );
  }

  return (
    <Modal
      hasCloseButton
      isOpen={isOpen}
      onClose={handleClose}
    >
      <ModalHeader
        title={modalTitle}
        className={styles.modalTitle}
        onShareClick={swapChain && swapTransactionInfo?.hash ? handleShareClick : undefined}
        onClose={handleClose}
      />
      {renderContent()}
    </Modal>
  );
}

export default memo(
  withGlobal((global): StateProps => {
    const accountState = selectCurrentAccountState(global);
    const account = selectCurrentAccount(global);
    const { isSwapDisabled } = global.restrictions;
    const { theme, isSensitiveDataHidden, isTestnet } = global.settings;

    const id = accountState?.currentActivityId;
    const activity = id ? accountState?.activities?.byId[id] : undefined;

    return {
      activity: activity?.kind === 'swap' ? activity : undefined,
      swapTokensBySlug: global.swapTokenInfo?.bySlug,
      tokensBySlug: global.tokenInfo.bySlug,
      theme,
      accountChains: account?.byChain,
      isSwapDisabled: isSwapDisabled || isTestnet || selectIsCurrentAccountViewMode(global),
      isSensitiveDataHidden,
      isTestnet,
      selectedExplorerIds: global.settings.selectedExplorerIds,
    };
  })(SwapActivityModal),
);

function getTransactionHash({ id, cex, hashes, from }: ApiSwapActivity) {
  const chain = getChainBySlug(from);

  if (!cex) {
    return {
      hash: parseTxId(id).hash,
      chain,
    };
  }

  if (!hashes[0]) {
    return undefined;
  }

  return {
    hash: hashes[0],
    chain, // Assuming the backend always returns the "from" transaction hash as the first hash
  };
}

function AddressQr({ isActive, address }: { isActive: boolean; address: string }) {
  const { qrCodeRef, isInitialized } = useQrCode({
    address,
    isActive,
    hiddenClassName: styles.qrCodeHidden,
    hideLogo: true,
  });

  return <div className={buildClassName(styles.qrCode, !isInitialized && styles.qrCodeHidden)} ref={qrCodeRef} />;
}
