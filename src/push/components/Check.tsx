import type { Wallet } from '@tonconnect/sdk';
import React, { memo, useLayoutEffect, useMemo, useRef, useState } from '../../lib/teact/teact';

import type { ApiCheck } from '../types';
import type { ParticleConfig } from '../util/particles';

import { PUSH_CHAIN, PUSH_SC_VERSIONS, PUSH_START_PARAM_DELIMITER } from '../config';
import { areDeepEqual } from '../../util/areDeepEqual';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { getTelegramApp } from '../../util/telegram';
import { getExplorerAddressUrl, getExplorerTransactionUrl } from '../../util/url';
import {
  fetchAccountBalance,
  fetchCheck,
  processCancelCheck,
  processCashCheck,
  processCreateCheck,
  processToggleInvoice,
} from '../util/check';
import { PARTICLE_COLORS, setupParticles } from '../util/particles';
import { getWalletAddress } from '../util/tonConnect';

import useFlag from '../../hooks/useFlag';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useSyncEffect from '../../hooks/useSyncEffect';

import AnimatedIconWithPreview from '../../components/ui/AnimatedIconWithPreview';
import Image from '../../components/ui/Image';
import Transition from '../../components/ui/Transition';
import Header from './Header';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';
import styles from './Check.module.scss';

import svgClockPath from '../assets/clock_light_gray.svg';
import lottieClockPath from '../assets/clock_light_gray.tgs';
import logoMyPath from '../assets/logo_my.svg';
import logoPushPath from '../assets/logo_push.png';
import logoTonPath from '../assets/logo_ton.svg';
import logoUsdtPath from '../assets/logo_usdt.svg';

interface OwnProps {
  isActive: boolean;
  wallet?: Wallet;
  check?: ApiCheck;
  setCheck: (check: ApiCheck | undefined) => void;
  isJustSentRequest: boolean;
  markJustSentRequest: NoneToVoidFunction;
  onConnectClick: () => Promise<void>;
  onDisconnectClick: NoneToVoidFunction;
  onForwardClick: NoneToVoidFunction;
}

const POLLING_INTERVAL = 3000;
const PLACEHOLDER = '···';

const PARTICLE_PARAMS: Partial<ParticleConfig> = {
  width: 350,
  height: 230,
  particleCount: 35,
  centerShift: [0, 32] as const,
  distanceLimit: 0.45,
};

const PARTICLE_BURST_PARAMS: Partial<ParticleConfig> = {
  particleCount: 90,
  distanceLimit: 1,
  fadeInTime: 0.05,
  minLifetime: 3,
  maxLifetime: 3,
  maxStartTimeDelay: 0,
  selfDestroyTime: 3,
  minSpawnRadius: 35,
  maxSpawnRadius: 50,
};

let activeKey = 0;

function Check({
  isActive,
  wallet,
  check,
  setCheck,
  isJustSentRequest,
  markJustSentRequest,
  onConnectClick,
  onDisconnectClick,
  onForwardClick,
}: OwnProps) {
  const canvasRef = useRef<HTMLCanvasElement>();

  const lang = useLang();

  const checkKey = useMemo(() => {
    const tgWebAppData = getTelegramApp()?.initDataUnsafe;
    const [action, checkKey2] = tgWebAppData?.start_param?.split(PUSH_START_PARAM_DELIMITER) ?? [];

    return action === 'check' ? checkKey2 : undefined;
  }, []);

  const [checkError, setCheckError] = useState<Error>();
  const [accountBalance, setAccountBalance] = useState<string>();
  const [isJustSentCancelRequest, markIsJustSentCancelRequest] = useFlag(false);

  const checkSymbol = check?.type === 'coin' ? check.symbol : undefined;

  useInterval(async () => {
    if (!checkKey) return;

    try {
      const newCheck = await fetchCheck(checkKey);

      setCheck(areDeepEqual(check, newCheck) ? check : newCheck);
      setCheckError(undefined);

      if (wallet) {
        const newAccountBalance = await fetchAccountBalanceFromWalletAndCheck(wallet, newCheck);

        setAccountBalance(newAccountBalance);
      }
    } catch (err: any) {
      setCheckError(err as Error);
    }
  }, POLLING_INTERVAL);

  useSyncEffect(() => {
    if (wallet && check) {
      void fetchAccountBalanceFromWalletAndCheck(wallet, check).then(setAccountBalance);
    }
  }, [wallet, check]);

  const [isLoading, markLoading, unmarkLoading] = useFlag(false);

  const { isCurrentUserSender, status } = check || {};
  const isCurrentUserPayer = (isCurrentUserSender && !check?.isInvoice) || (!isCurrentUserSender && check?.isInvoice);

  const hasError = Boolean(checkError);
  useSyncEffect(() => {
    activeKey++;
  }, [status, isJustSentRequest, isJustSentCancelRequest, hasError]);

  useLayoutEffect(() => {
    if (!checkSymbol) return;

    return setupParticles(canvasRef.current!, {
      color: PARTICLE_COLORS[checkSymbol],
      ...PARTICLE_PARAMS,
    });
  }, [checkSymbol]);

  const handleTokenClick = useLastCallback(() => {
    if (check?.type !== 'coin') return;

    setupParticles(canvasRef.current!, {
      color: PARTICLE_COLORS[check.symbol],
      ...PARTICLE_PARAMS,
      ...PARTICLE_BURST_PARAMS,
    });
  });

  const handleConnectClick = useLastCallback(async () => {
    markLoading();
    await onConnectClick();
    unmarkLoading();
  });

  const handleDisconnectClick = useLastCallback((e) => {
    e.preventDefault();
    void onDisconnectClick();
  });

  const handleSignClick = useLastCallback(async () => {
    markLoading();
    await processCreateCheck(check!, markJustSentRequest);
    unmarkLoading();
  });

  const handleToggleInvoiceClick = useLastCallback(async () => {
    markLoading();

    const isInvoice = await processToggleInvoice(check!, markJustSentRequest);
    if (isInvoice !== undefined) {
      setCheck({ ...check!, isInvoice });
    }

    unmarkLoading();
  });

  const handleReceiveClick = useLastCallback(async () => {
    markLoading();

    try {
      await processCashCheck(check!, markJustSentRequest, getWalletAddress(wallet!));
    } catch (err: any) {
      alert(String(err));
    }

    unmarkLoading();
  });

  const handleCancelTransferClick = useLastCallback(async () => {
    markLoading();

    try {
      const isV3 = PUSH_SC_VERSIONS.v3.includes(check!.contractAddress)
        || PUSH_SC_VERSIONS.NFT === check!.contractAddress;
      if (isV3) {
        await processCancelCheck(check!, markIsJustSentCancelRequest);
      } else {
        await processCashCheck(check!, markIsJustSentCancelRequest, getWalletAddress(wallet!), true);
      }
    } catch (err: any) {
      alert(String(err));
    }

    unmarkLoading();
  });

  const handleCloseClick = useLastCallback(() => {
    getTelegramApp()?.close();
    window.close();
  });

  const action = isCurrentUserPayer ? 'sending' : 'receiving';

  const imgPath = !checkKey
    ? logoPushPath
    : !check
      ? undefined
      : check.type === 'nft'
        ? check.nftInfo.imageUrl
        : check.symbol === 'USDT'
          ? logoUsdtPath
          : check.symbol === 'MY'
            ? logoMyPath
            : logoTonPath;

  const walletUrl = useMemo(() => (
    wallet ? getExplorerAddressUrl(PUSH_CHAIN, getWalletAddress(wallet)) : undefined
  ), [wallet]);
  const txUrl = useMemo(() => (
    check?.txId ? getExplorerTransactionUrl(PUSH_CHAIN, check.txId.split(':')[1]) : undefined
  ), [check?.txId]);

  function renderBadge() {
    const hasCheckBadge = status === 'received' || (
      isCurrentUserPayer && isJustSentRequest && status === 'pending_receive'
    );

    const hasClockBadge = !hasCheckBadge && status !== 'failed' && (isJustSentRequest || (status && (
      (isCurrentUserPayer && status !== 'pending_signature')
      || (!isCurrentUserPayer && status !== 'pending_receive')
    )));

    return (
      <Transition
        name="semiFade"
        activeKey={hasClockBadge ? 1 : hasCheckBadge ? 2 : 0}
        className={styles.tokenBadgeTransition}
      >
        {hasClockBadge ? (
          <div className={buildClassName(styles.tokenBadge, styles.tokenBadge_clock)}>
            <AnimatedIconWithPreview
              play
              size={32}
              className={styles.iconClock}
              nonInteractive
              noLoop={false}
              forceOnHeavyAnimation
              tgsUrl={lottieClockPath}
              previewUrl={svgClockPath}
            />
          </div>
        ) : hasCheckBadge && (
          <div className={buildClassName(styles.tokenBadge, styles.tokenBadge_check)} />
        )}
      </Transition>
    );
  }

  function renderStatus() {
    const statusText = lang(!checkKey ? (
      'Secure crypto transfers on Telegram'
    ) : checkError ? (
      'Transfer not found'
    ) : !check ? (
      'Loading...'
    ) : status === 'pending_signature' ? (
      isCurrentUserPayer ? (
        isJustSentRequest ? (
          'Confirming...'
        ) : wallet ? (
          'Confirm transfer in wallet'
        ) : (
          'Connect wallet to transfer'
        )
      ) : (
        'Waiting sender confirmation...'
      )
    ) : status === 'sending' ? (
      isCurrentUserPayer ? (
        isJustSentRequest ? (
          'Confirming...'
        ) : (
          'Still confirming...'
        )
      ) : (
        'Waiting sender confirmation...'
      )
    ) : status === 'pending_receive' ? (
      isCurrentUserPayer ? (
        isJustSentCancelRequest ? (
          'Returning...'
        ) : isJustSentRequest ? (
          'Confirmed'
        ) : (
          'Waiting for the recipient...'
        )
      ) : (
        isJustSentRequest ? (
          'Receiving...'
        ) : wallet ? (
          'Ready to receive'
        ) : (
          'Connect wallet or forward to any address'
        )
      )
    ) : status === 'receiving' ? (
      isCurrentUserPayer || isJustSentRequest ? (
        isJustSentCancelRequest ? (
          'Returning...'
        ) : (
          'Receiving...'
        )
      ) : (
        'Still receiving...'
      )
    ) : status === 'received' ? (
      !isCurrentUserPayer && check.receiverAddress && wallet && check.receiverAddress !== getWalletAddress(wallet) ? (
        'Received by another person'
      ) : (
        'Received'
      )
    ) : status === 'failed' ? (
      'Returned'
    ) : (
      'Unexpected error'
    ));

    if (check?.txId) {
      return (
        <a href={txUrl} target="_blank" rel="noreferrer" className={styles.statusLink}>
          {statusText}
          <i className={styles.txIcon} />
        </a>
      );
    } else if (checkError) {
      return (
        <a href="https://t.me/push?start=why_not_found" rel="noreferrer" className={styles.statusLink}>
          {statusText}
          <i className={styles.whyNotFoundIcon} />
        </a>
      );
    }

    return statusText;
  }

  function renderButtons(areButtonsActive: boolean) {
    let primaryText: string | undefined;
    let primaryOnClick: NoneToVoidFunction | undefined;
    let isPrimarySecondary = false;

    let secondaryText: string | undefined;
    let secondaryOnClick: NoneToVoidFunction | undefined;

    const isActionAvailable = (
      (isCurrentUserPayer && (status === 'pending_signature' || status === 'sending') && !isJustSentRequest)
      || (isCurrentUserPayer && status === 'pending_receive' && !isJustSentCancelRequest)
      || (!isCurrentUserPayer && (status === 'pending_receive' || status === 'receiving') && !isJustSentRequest)
    );

    if (checkError) {
      primaryText = lang('Close');
      primaryOnClick = handleCloseClick;
    } else if (!wallet && isActionAvailable) {
      primaryText = lang('Connect Wallet');
      primaryOnClick = handleConnectClick;
    } else if (isCurrentUserPayer && status === 'pending_signature' && !isJustSentRequest) {
      primaryText = lang('Confirm in Wallet');
      primaryOnClick = handleSignClick;
    } else if (isCurrentUserPayer && status === 'sending' && !isJustSentRequest) {
      primaryText = lang('Confirm Again');
      primaryOnClick = handleSignClick;
      isPrimarySecondary = true;
    } else if (!isCurrentUserPayer && status === 'pending_receive' && !isJustSentRequest) {
      primaryText = lang('Receive');
      primaryOnClick = handleReceiveClick;
    } else if (!isCurrentUserPayer && status === 'receiving' && !isJustSentRequest) {
      primaryText = lang('Try Receiving Again');
      primaryOnClick = handleReceiveClick;
      isPrimarySecondary = true;
    } else {
      primaryText = lang('Close');
      primaryOnClick = handleCloseClick;
    }

    if (isCurrentUserSender && status === 'pending_signature' && !isJustSentRequest && check?.type === 'coin') {
      secondaryText = isCurrentUserPayer ? lang('Request Payment') : lang('Pay Myself');
      secondaryOnClick = handleToggleInvoiceClick;
    } else if (isCurrentUserPayer && wallet && status === 'pending_receive' && !isJustSentCancelRequest) {
      secondaryText = lang('Cancel Transfer');
      secondaryOnClick = handleCancelTransferClick;
    } else if (!isCurrentUserPayer && isActionAvailable) {
      secondaryText = lang('Forward to Address');
      secondaryOnClick = onForwardClick;
    }

    return (
      <>
        {primaryText && primaryOnClick && (
          <UniversalButton
            isPrimary={!isPrimarySecondary}
            isActive={areButtonsActive}
            isLoading={isLoading}
            className={commonStyles.button}
            onClick={primaryOnClick}
          >
            {primaryText}
          </UniversalButton>
        )}
        {secondaryText && secondaryOnClick && (
          <UniversalButton
            isSecondary
            isActive={areButtonsActive}
            isDisabled={isLoading}
            className={buildClassName(commonStyles.button, commonStyles.button_secondary)}
            onClick={secondaryOnClick}
          >
            {secondaryText}
          </UniversalButton>
        )}
      </>
    );
  }

  return (
    <div className={buildClassName(commonStyles.container, commonStyles.container_centered)}>
      <Header
        accountBalance={accountBalance}
        symbol={(check?.type === 'coin' && check.symbol) || 'TON'}
        walletUrl={walletUrl}
        onDisconnectClick={handleDisconnectClick}
      />

      <div className={styles.tokenContainer}>
        <canvas ref={canvasRef} className={styles.particles} />
        <div className={styles.tokenLogo}>
          <div className={styles.tokenImgContainer} onClick={check ? handleTokenClick : undefined}>
            {imgPath && (
              <Image
                url={imgPath}
                isSlow
                alt={(check?.type === 'coin'
                  ? check.symbol
                  : check?.nftInfo.name) || 't.me/push'}
                imageClassName={styles.tokenImg}
              />
            )}
          </div>
          {renderBadge()}
        </div>
      </div>

      <Transition
        name="semiFade"
        activeKey={activeKey}
        className={styles.mainTransition}
        slideClassName={styles.mainTransitionSlide}
      >
        {(isMainActive) => (
          <>
            <div
              className={
                buildClassName(
                  commonStyles.roundedFont,
                  styles.amount,
                  check?.type === 'coin' && styles[`amount_${action}`],
                )
              }
            >
              {!checkKey ? (
                <a href="https://t.me/push?start=1">t.me/push</a>
              ) : check?.type === 'coin' ? (
                check.amount ? (
                  formatCurrency(check.amount, check.symbol)
                ) : (
                  PLACEHOLDER
                )
              ) : (
                check?.nftInfo!.name || PLACEHOLDER
              )}
            </div>

            <div className={styles.status}>
              {renderStatus()}
            </div>

            <div
              className={buildClassName(
                styles.comment,
                styles[`comment_${action}`],
                !check?.comment && styles.comment_empty,
              )}
            >
              {check?.comment}
            </div>

            <div className={commonStyles.footer}>
              {renderButtons(isActive && isMainActive)}
            </div>
          </>
        )}
      </Transition>
    </div>
  );
}

export default memo(Check);

async function fetchAccountBalanceFromWalletAndCheck(wallet: Wallet, check: ApiCheck) {
  if (!wallet || !check) return;

  const minterAddress = check.type === 'coin' ? check.minterAddress : undefined;
  const balanceBig = await fetchAccountBalance(getWalletAddress(wallet), minterAddress);

  const decimals = check.type === 'coin' ? check.decimals : 9;
  return toDecimal(balanceBig, decimals);
}
