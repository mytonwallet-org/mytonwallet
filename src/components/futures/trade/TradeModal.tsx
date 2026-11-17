import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { ApiPerpsMarketAsset } from '../../../api/types';
import type { PerpsTradeState, PerpsTradeStep } from '../../../global/types';
import { SwapState } from '../../../global/types';

import { getIsPerpsAccountDisabled } from '../../../global/helpers/perps';
import { selectPerpsMarketAsset } from '../../../global/selectors';
import buildClassName from '../../../util/buildClassName';
import resolveSlideTransitionName from '../../../util/resolveSlideTransitionName';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import useLastCallback from '../../../hooks/useLastCallback';
import useModalTransitionKeys from '../../../hooks/useModalTransitionKeys';

import AccountSwitcherSlide from '../../common/AccountSwitcherSlide';
import Modal from '../../ui/Modal';
import Transition from '../../ui/Transition';
import BalanceWithdrawal from './BalanceWithdrawal';
import OperationStatus from './OperationStatus';
import TradeForm from './TradeForm';
import TradePassword from './TradePassword';
import TradeProgress from './TradeProgress';
import TradeReceipt from './TradeReceipt';
import TradeReview from './TradeReview';
import Withdrawal from './Withdrawal';

import modalStyles from '../../ui/Modal.module.scss';
import styles from './TradeModal.module.scss';

interface StateProps {
  trade?: PerpsTradeState;
  asset?: ApiPerpsMarketAsset;
  isSwapOpen: boolean;
}

// Later steps get larger keys, so the slide transition plays forward as the trade goes on
const enum Slide {
  Form,
  SelectAccount,
  Review,
  Password,
  Progress,
  Status,
  Withdrawal,
  BalanceWithdrawal,
}

// The receipt opens in a modal of its own, so the trade modal keeps its last slide while it closes
const SLIDE_BY_STEP: Record<PerpsTradeStep, Slide> = {
  form: Slide.Form,
  selectAccount: Slide.SelectAccount,
  review: Slide.Review,
  password: Slide.Password,
  progress: Slide.Progress,
  receipt: Slide.Progress,
  status: Slide.Status,
  withdrawal: Slide.Withdrawal,
  withdrawalPassword: Slide.Password,
  balanceWithdrawal: Slide.BalanceWithdrawal,
  balanceWithdrawalPassword: Slide.Password,
};

function TradeModal({ trade, asset, isSwapOpen }: StateProps) {
  const { cancelPerpsTrade, setPerpsTradeStep, switchPerpsTradeAccount } = getActions();

  const handleAccountSelect = useLastCallback((accountId: string) => {
    switchPerpsTradeAccount({ accountId });
  });

  const handleAccountSelectBack = useLastCallback(() => {
    setPerpsTradeStep({ step: 'form' });
  });

  // Closing modals keep showing the trade they were opened for
  const renderedTrade = useCurrentOrPrev(trade, true);
  const renderedAsset = useCurrentOrPrev(asset, true);
  // The purchase of a missing token covers the form, and the form comes back with the same values afterwards. A
  // balance withdrawal and a close open only after their first quote arrives. Until then, the button that started
  // them shows a spinner.
  const isOpen = Boolean(trade && trade.step !== 'receipt')
    && !(trade?.step === 'balanceWithdrawal' && !trade.balanceWithdrawal)
    && !(trade?.kind === 'close' && !trade.quote)
    && !isSwapOpen;
  const isReceiptOpen = trade?.step === 'receipt';
  const receiptTrade = useCurrentOrPrev(isReceiptOpen ? trade : undefined, true);
  const { renderingKey } = useModalTransitionKeys(trade ? SLIDE_BY_STEP[trade.step] : Slide.Form, isOpen);

  function renderContent(isActive: boolean, _: boolean, currentKey: Slide) {
    switch (currentKey) {
      case Slide.Form:
        return <TradeForm isActive={isOpen && isActive} trade={renderedTrade!} asset={renderedAsset} />;
      case Slide.SelectAccount:
        return (
          <AccountSwitcherSlide
            isActive={isActive}
            getIsAccountDisabled={getIsPerpsAccountDisabled}
            onAccountSelect={handleAccountSelect}
            onBack={handleAccountSelectBack}
            onClose={cancelPerpsTrade}
          />
        );
      case Slide.Review:
        return <TradeReview isActive={isActive} trade={renderedTrade!} asset={renderedAsset} />;
      case Slide.Password:
        return <TradePassword isActive={isActive} trade={renderedTrade!} asset={renderedAsset} />;
      case Slide.Progress:
        return <TradeProgress trade={renderedTrade!} asset={renderedAsset} />;
      case Slide.Status:
        return <OperationStatus trade={renderedTrade!} asset={renderedAsset} />;
      case Slide.Withdrawal:
        return <Withdrawal isActive={isActive} trade={renderedTrade!} />;
      case Slide.BalanceWithdrawal:
        return <BalanceWithdrawal isActive={isActive} trade={renderedTrade!} />;
    }
  }

  return (
    <>
      <Modal isOpen={isOpen} dialogClassName={styles.dialog} onClose={cancelPerpsTrade}>
        <Transition
          name={resolveSlideTransitionName()}
          className={buildClassName(modalStyles.transition, modalStyles.transition_stableScroll, 'custom-scroll')}
          slideClassName={modalStyles.transitionSlide}
          activeKey={renderingKey}
        >
          {renderContent}
        </Transition>
      </Modal>
      <Modal isOpen={isReceiptOpen} dialogClassName={styles.receiptDialog} onClose={cancelPerpsTrade}>
        {receiptTrade && <TradeReceipt trade={receiptTrade} asset={renderedAsset} />}
      </Modal>
    </>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { trade } = global.perps;

  return {
    trade,
    asset: trade && selectPerpsMarketAsset(global, trade.assetId),
    isSwapOpen: global.currentSwap.state !== SwapState.None,
  };
})(TradeModal));
