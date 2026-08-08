import React, {
  memo, useEffect, useMemo, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiActivity } from '../../api/types';
import type { Account, GlobalState, UserSwapToken, UserToken } from '../../global/types';
import { SwapState, SwapType } from '../../global/types';

import {
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectHasMultipleAccounts,
  selectSwapTokens,
  selectSwapType,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { formatCurrencyExtended } from '../../util/formatNumber';
import { getIsViewAccountDisabled } from '../../util/isViewAccount';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import AccountSwitcherPill from '../common/AccountSwitcherPill';
import AccountSwitcherSlide from '../common/AccountSwitcherSlide';
import TokenSelector from '../common/TokenSelector';
import TransactionBanner from '../common/TransactionBanner';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';
import SwapBlockchain from './SwapBlockchain';
import SwapComplete from './SwapComplete';
import SwapInitial from './SwapInitial';
import SwapMfaConfirm from './SwapMfaConfirm';
import SwapPassword from './SwapPassword';
import SwapWaitTokens from './SwapWaitTokens';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

interface StateProps {
  currentSwap: GlobalState['currentSwap'];
  swapType: SwapType;
  swapTokens?: UserSwapToken[];
  activityById?: Record<string, ApiActivity>;
  accountChains?: Account['byChain'];
  accountId?: string;
  accountTitle?: string;
  hasMultipleAccounts?: boolean;
}

function SwapModal({
  currentSwap: {
    state,
    tokenInSlug,
    tokenOutSlug,
    amountIn = '0',
    amountOut = '0',
    isLoading,
    error,
    activityId,
    toAddress,
    payinAddress,
    payoutAddress,
    payinExtraId,
    isManualDepositRequired,
    currentCexLabel,
  },
  swapType,
  swapTokens,
  activityById,
  accountChains,
  accountId,
  accountTitle,
  hasMultipleAccounts,
}: StateProps) {
  const {
    startSwap,
    cancelSwap,
    setSwapScreen,
    submitSwap,
    showActivityInfo,
    submitSwapCex,
    addSwapToken,
    setSwapTokenIn,
    setSwapTokenOut,
    switchSwapAccount,
  } = getActions();
  const lang = useLang();

  const isOpen = state !== SwapState.None;
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const tokenIn = useMemo(
    () => swapTokens?.find((token) => token.slug === tokenInSlug),
    [tokenInSlug, swapTokens],
  );

  const tokenOut = useMemo(
    () => swapTokens?.find((token) => token.slug === tokenOutSlug),
    [swapTokens, tokenOutSlug],
  );

  const [renderedSwapType, setRenderedSwapType] = useState(swapType);
  const [renderedTransactionAmountIn, setRenderedTransactionAmountIn] = useState(amountIn);
  const [renderedTransactionAmountOut, setRenderedTransactionAmountOut] = useState(amountOut);
  const [renderedTransactionTokenIn, setRenderedTransactionTokenIn] = useState(tokenIn);
  const [renderedTransactionTokenOut, setRenderedTransactionTokenOut] = useState(tokenOut);
  const [renderedActivity, setRenderedActivity] = useState<ApiActivity | undefined>();
  const renderedCexLabel = renderedActivity?.kind === 'swap'
    ? renderedActivity.cexLabel ?? currentCexLabel
    : currentCexLabel;

  useEffect(() => {
    if (!isOpen || !activityId || !activityById?.[activityId]) {
      setRenderedActivity(undefined);
      return;
    }

    const activity = activityById[activityId];
    setRenderedActivity(activity);

    if (activity.kind === 'swap' && swapType === SwapType.CrosschainToWallet) {
      const status = activity.cex?.status;
      if (status === 'exchanging' || status === 'confirming') {
        setSwapScreen({ state: SwapState.Complete });
      }
    }
  }, [activityById, activityId, isOpen, swapType]);

  const handleTransferSubmit = useLastCallback((enclaveToken: string) => {
    setRenderedTransactionAmountIn(amountIn);
    setRenderedTransactionAmountOut(amountOut);
    setRenderedTransactionTokenIn(tokenIn);
    setRenderedTransactionTokenOut(tokenOut);
    setRenderedSwapType(swapType);

    if (swapType === SwapType.OnChain) {
      submitSwap({ enclaveToken });
      return;
    }

    submitSwapCex({ enclaveToken });
  });

  const handleBackClick = useLastCallback(() => {
    if (state === SwapState.Password) {
      if (swapType === SwapType.CrosschainFromWallet) {
        setSwapScreen({ state: SwapState.Blockchain });
      } else {
        setSwapScreen({ state: SwapState.Initial });
      }
      return;
    }

    if (state === SwapState.SelectTokenTo || state === SwapState.SelectTokenFrom) {
      setSwapScreen({ state: SwapState.Initial });
    }

    if (state === SwapState.Blockchain) {
      setSwapScreen({ state: SwapState.Initial });
    }
  });

  const handleTransactionInfoClick = useLastCallback(() => {
    if (!activityId) return;

    cancelSwap({ shouldReset: true });
    showActivityInfo({ id: activityId });
  });

  const handleModalClose = useLastCallback(() => {
    cancelSwap({ shouldReset: true });
    updateNextKey();
  });

  const handleModalCloseWithReset = useLastCallback(() => {
    cancelSwap({ shouldReset: true });
  });

  const handleTokenSelect = useLastCallback((token: UserSwapToken | UserToken) => {
    addSwapToken({ token: token as UserSwapToken });
    // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
    const setToken = renderingKey === SwapState.SelectTokenTo ? setSwapTokenOut : setSwapTokenIn;
    setToken({ tokenSlug: token.slug });
  });

  const handleStartSwap = useLastCallback(() => {
    startSwap({
      amountIn: renderedTransactionAmountIn,
      tokenInSlug: renderedTransactionTokenIn?.slug,
      tokenOutSlug: renderedTransactionTokenOut?.slug,
    });
  });

  const handleOpenAccountSelector = useLastCallback(() => {
    setSwapScreen({ state: SwapState.SelectAccount });
  });

  const handleSelectAccount = useLastCallback((nextAccountId: string) => {
    switchSwapAccount({ accountId: nextAccountId });
  });

  const handleSelectAccountBack = useLastCallback(() => {
    setSwapScreen({ state: SwapState.Initial });
  });

  function renderSwapShortInfo(
    bannerTokenIn = tokenIn,
    bannerTokenOut = tokenOut,
    bannerAmountIn = amountIn,
    bannerAmountOut = amountOut,
  ) {
    if (!bannerTokenIn || !bannerTokenOut || !bannerAmountIn || !bannerAmountOut) return undefined;

    return (
      <TransactionBanner
        tokenIn={bannerTokenIn}
        withChainIcon
        tokenOut={bannerTokenOut}
        text={formatCurrencyExtended(bannerAmountIn, bannerTokenIn.symbol ?? '', true)}
        secondText={formatCurrencyExtended(bannerAmountOut, bannerTokenOut.symbol ?? '', true)}
        className={!getDoesUsePinPad() ? styles.transactionBanner : undefined}
      />
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SwapState) {
    switch (currentKey) {
      case SwapState.Initial:
        return (
          <>
            <div
              className={buildClassName(styles.initialHeader, hasMultipleAccounts && styles.initialHeaderWithSwitcher)}
            >
              <ModalHeader
                title={lang('$swap_action')}
                onClose={cancelSwap}
              />
              {hasMultipleAccounts && accountId && (
                <AccountSwitcherPill
                  accountId={accountId}
                  title={accountTitle}
                  className={styles.accountPill}
                  onClick={handleOpenAccountSelector}
                />
              )}
            </div>
            <SwapInitial key={accountId} isActive={isActive} />
          </>
        );
      case SwapState.SelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsViewAccountDisabled}
            onAccountSelect={handleSelectAccount}
            onBack={handleSelectAccountBack}
            onClose={handleModalCloseWithReset}
          />
        );
      case SwapState.Blockchain:
        return (
          <SwapBlockchain
            isActive={isActive}
            toAddress={toAddress}
            tokenIn={tokenIn}
            tokenOut={tokenOut}
            swapType={swapType}
            cexLabel={currentCexLabel}
          />
        );
      case SwapState.WaitTokens:
        return (
          <SwapWaitTokens
            isActive={isActive}
            tokenIn={renderedTransactionTokenIn}
            tokenOut={renderedTransactionTokenOut}
            amountIn={renderedTransactionAmountIn}
            amountOut={renderedTransactionAmountOut}
            payinAddress={payinAddress}
            payoutAddress={payoutAddress}
            payinExtraId={payinExtraId}
            isManualDepositRequired={isManualDepositRequired}
            cexLabel={renderedCexLabel}
            accountChains={accountChains}
            activity={renderedActivity}
            onClose={handleModalCloseWithReset}
          />
        );
      case SwapState.Password:
        return (
          <SwapPassword
            isActive={isActive}
            isLoading={isLoading}
            error={error}
            onAuthorize={handleTransferSubmit}
            onBack={handleBackClick}
          >
            {renderSwapShortInfo()}
          </SwapPassword>
        );
      case SwapState.ConfirmMfa:
        return (
          <SwapMfaConfirm
            isActive={isActive}
            onClose={handleModalCloseWithReset}
          >
            {renderSwapShortInfo(
              renderedTransactionTokenIn,
              renderedTransactionTokenOut,
              renderedTransactionAmountIn,
              renderedTransactionAmountOut,
            )}
          </SwapMfaConfirm>
        );
      case SwapState.Complete: {
        return (
          <SwapComplete
            isActive={isActive}
            tokenIn={renderedTransactionTokenIn}
            tokenOut={renderedTransactionTokenOut}
            amountIn={renderedTransactionAmountIn}
            amountOut={renderedTransactionAmountOut}
            swapType={renderedSwapType}
            cexLabel={renderedCexLabel}
            toAddress={toAddress}
            onClose={handleModalCloseWithReset}
            onInfoClick={handleTransactionInfoClick}
            onStartSwap={handleStartSwap}
            isDetailsDisabled={!activityId}
          />
        );
      }
      case SwapState.SelectTokenFrom:
      case SwapState.SelectTokenTo:
        return (
          <TokenSelector
            isActive={isActive}
            shouldUseSwapTokens
            shouldFilter={currentKey === SwapState.SelectTokenTo}
            isSwapOut={currentKey === SwapState.SelectTokenTo}
            onTokenSelect={handleTokenSelect}
            onBack={handleBackClick}
            onClose={handleModalCloseWithReset}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={cancelSwap}
      dialogClassName={styles.modalDialog}
      hasCloseButton
      onCloseAnimationEnd={handleModalClose}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={renderingKey}
        nextKey={nextKey}
        onStop={updateNextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(withGlobal((global): StateProps => {
  const accountState = selectCurrentAccountState(global);
  const account = selectCurrentAccount(global);
  const activityById = accountState?.activities?.byId;

  return {
    currentSwap: global.currentSwap,
    swapType: selectSwapType(global),
    swapTokens: selectSwapTokens(global),
    activityById,
    accountChains: account?.byChain,
    accountId: selectCurrentAccountId(global),
    accountTitle: account?.title,
    hasMultipleAccounts: selectHasMultipleAccounts(global),
  };
})(SwapModal));
