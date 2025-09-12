import React, { memo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiTokenWithPrice } from '../../api/types';
import type { UserSwapToken, UserToken } from '../../global/types';

import { IS_CAPACITOR, TONCOIN } from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectAccount, selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { fromDecimal } from '../../util/decimals';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import formatTransferUrl from '../../util/ton/formatTransferUrl';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import SelectTokenButton from '../common/SelectTokenButton';
import TokenSelector from '../common/TokenSelector';
import Input from '../ui/Input';
import InteractiveTextField from '../ui/InteractiveTextField';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import RichNumberInput from '../ui/RichNumberInput';
import Transition from '../ui/Transition';

import modalStyles from '../ui/Modal.module.scss';
import styles from './ReceiveModal.module.scss';

interface StateProps {
  isOpen?: boolean;
  tokenSlug?: string;
  tokensBySlug?: Record<string, ApiTokenWithPrice>;
  address?: string;
}

const enum SLIDES {
  Initial,
  Selector,
}

function InvoiceModal({
  address,
  tokenSlug,
  tokensBySlug,
  isOpen,
}: StateProps) {
  const { changeInvoiceToken, closeInvoiceModal } = getActions();

  const lang = useLang();
  const selectedToken = tokensBySlug && tokenSlug ? tokensBySlug[tokenSlug] : TONCOIN;
  const [isTokenSelectorOpen, openTokenSelector, closeTokenSelector] = useFlag(false);
  const [amountValue, setAmountValue] = useState<string | undefined>(undefined);
  const [comment, setComment] = useState<string>('');

  const decimals = selectedToken?.decimals ?? TONCOIN.decimals;
  const amount = amountValue ? fromDecimal(amountValue, decimals) : 0n;
  const tokenAddress = 'tokenAddress' in selectedToken ? selectedToken?.tokenAddress : undefined;
  const invoiceUrl = address ? formatTransferUrl(address, amount, comment, tokenAddress) : '';

  const handleTokenSelect = useLastCallback((token: UserToken | UserSwapToken) => {
    changeInvoiceToken({ tokenSlug: token.slug });
  });

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.Initial:
        return (
          <>
            <ModalHeader
              title={lang('Deposit Link')}
              onClose={closeInvoiceModal}
            />
            <div className={styles.content}>
              <div className={styles.contentTitle}>
                {renderText(lang('$receive_invoice_description'))}
              </div>
              <RichNumberInput
                key="amount"
                id="amount"
                value={amountValue}
                labelText={lang('Amount')}
                onChange={setAmountValue}
              >
                <SelectTokenButton
                  noChainIcon
                  token={selectedToken}
                  className={styles.tokenButton}
                  onClick={openTokenSelector}
                />
              </RichNumberInput>
              <Input
                value={comment}
                label={lang('Comment')}
                placeholder={lang('Optional')}
                wrapperClassName={styles.invoiceComment}
                onInput={setComment}
              />

              <p className={styles.labelForInvoice}>
                {lang('Share this URL to receive %token%', { token: selectedToken?.symbol })}
              </p>
              <InteractiveTextField
                text={invoiceUrl}
                addressUrl={IS_CAPACITOR ? invoiceUrl : undefined}
                noExplorer
                withShareInMenu={IS_CAPACITOR}
                copyNotification={lang('Invoice link was copied!')}
                className={styles.invoiceLinkField}
              />
            </div>
          </>
        );

      case SLIDES.Selector:
        return (
          <TokenSelector
            isActive={isActive}
            shouldHideNotSupportedTokens
            selectedChain="ton"
            onTokenSelect={handleTokenSelect}
            onBack={closeTokenSelector}
            onClose={closeInvoiceModal}
          />
        );
    }
  }

  return (
    <Modal
      isOpen={isOpen}
      dialogClassName={styles.modalDialog}
      nativeBottomSheetKey="invoice"
      onClose={closeInvoiceModal}
      onCloseAnimationEnd={closeTokenSelector}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={modalStyles.transitionSlide}
        activeKey={isTokenSelectorOpen ? SLIDES.Selector : SLIDES.Initial}
        nextKey={isTokenSelectorOpen ? SLIDES.Initial : SLIDES.Selector}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

export default memo(
  withGlobal((global): StateProps => {
    const address = selectAccount(global, global.currentAccountId!)?.byChain.ton?.address;
    const { invoiceTokenSlug } = selectCurrentAccountState(global) || {};

    return {
      isOpen: global.isInvoiceModalOpen,
      tokenSlug: invoiceTokenSlug,
      tokensBySlug: global.tokenInfo?.bySlug,
      address,
    };
  })(InvoiceModal),
);
