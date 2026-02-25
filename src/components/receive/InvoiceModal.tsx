import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiTokenWithPrice } from '../../api/types';
import type { Account, UserSwapToken, UserToken } from '../../global/types';

import { DEFAULT_CHAIN, IS_CAPACITOR } from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectCurrentAccount, selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';
import { fromDecimal } from '../../util/decimals';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { getChainBySlug } from '../../util/tokens';

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
  byChain?: Account['byChain'];
}

const enum SLIDES {
  Initial,
  Selector,
}

function InvoiceModal({
  byChain,
  tokenSlug,
  tokensBySlug,
  isOpen,
}: StateProps) {
  const { changeInvoiceToken, closeInvoiceModal } = getActions();

  const selectedChain = tokenSlug ? getChainBySlug(tokenSlug) : DEFAULT_CHAIN;
  const { isTransferPayloadSupported, nativeToken, formatTransferUrl } = getChainConfig(selectedChain);
  const selectedToken = (tokenSlug && tokensBySlug?.[tokenSlug]) || nativeToken;
  const address = byChain?.[selectedChain]?.address;

  const lang = useLang();
  const [isTokenSelectorOpen, openTokenSelector, closeTokenSelector] = useFlag(false);
  const [amountValue, setAmountValue] = useState<string | undefined>(undefined);
  const [comment, setComment] = useState<string>('');

  const avalableChains = useMemo(
    () => byChain
      ? (Object.keys(byChain) as (keyof typeof byChain)[]).filter((chain) => getChainConfig(chain).formatTransferUrl)
      : [],
    [byChain],
  );

  const amount = amountValue ? fromDecimal(amountValue, selectedToken.decimals) : 0n;
  const tokenAddress = 'tokenAddress' in selectedToken ? selectedToken?.tokenAddress : undefined;
  const invoiceUrl = address && formatTransferUrl ? formatTransferUrl(address, amount, comment, tokenAddress) : '';

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
                  noChainIcon={avalableChains.length <= 1}
                  token={selectedToken}
                  className={styles.tokenButton}
                  onClick={openTokenSelector}
                />
              </RichNumberInput>
              {isTransferPayloadSupported && (
                <Input
                  value={comment}
                  label={lang('Comment')}
                  placeholder={lang('Optional')}
                  wrapperClassName={styles.invoiceComment}
                  onInput={setComment}
                />
              )}

              <p className={styles.labelForInvoice}>
                {lang('Share this URL to receive %token%', { token: selectedToken?.symbol })}
              </p>
              <InteractiveTextField
                text={invoiceUrl}
                addressUrl={IS_CAPACITOR ? invoiceUrl : undefined}
                noExplorer
                withShareInMenu={IS_CAPACITOR}
                copyNotification={lang('Invoice Link Copied')}
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
            selectedChain={avalableChains}
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
    const account = selectCurrentAccount(global);
    const { invoiceTokenSlug } = selectCurrentAccountState(global) || {};

    return {
      isOpen: global.isInvoiceModalOpen,
      tokenSlug: invoiceTokenSlug,
      tokensBySlug: global.tokenInfo?.bySlug,
      byChain: account?.byChain,
    };
  })(InvoiceModal),
);
