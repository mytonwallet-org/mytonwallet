import React, { memo, useEffect, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { WcPayPaymentOption } from '../../api/dappProtocols/adapters/walletConnect/types';
import type { ApiToken } from '../../api/types';
import type { GlobalState } from '../../global/types';
import { WalletConnectPayState } from '../../global/types';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import { pick } from '../../util/iteratees';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';

import TransactionBanner from '../common/TransactionBanner';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Modal from '../ui/Modal';
import ModalHeader from '../ui/ModalHeader';
import PasswordForm from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import WalletConnectPayAmount from './WalletConnectPayAmount';
import WalletConnectPayHeader from './WalletConnectPayHeader';
import WalletConnectPayMerchantLogo from './WalletConnectPayMerchantLogo';

import modalStyles from '../ui/Modal.module.scss';
import styles from './WalletConnectPay.module.scss';

type StateProps = Pick<
  GlobalState['currentWalletConnectPay'],
  'state' | 'operation' | 'isLoading' | 'error' | 'merchant' | 'paymentAmount'
  | 'paymentOption' | 'isSignOnly'
> & {
  tokensBySlug: Record<string, ApiToken>;
};

function WalletConnectPayModal({
  state,
  operation,
  isLoading,
  error,
  merchant,
  paymentAmount,
  paymentOption,
  isSignOnly,
  tokensBySlug,
}: StateProps) {
  const {
    submitWalletConnectPaySignData,
    submitWalletConnectPaySignTransaction,
    clearWalletConnectPayError,
    closeWalletConnectPay,
    cancelWalletConnectPay,
  } = getActions();

  const lang = useLang();
  const isSignData = operation === 'signData';
  const isOpen = state !== WalletConnectPayState.None;
  const { renderingKey, nextKey, updateNextKey } = useModalTransitionKeys(state, isOpen);

  const title = isSignData ? lang('Sign Data') : lang('Confirm Sending');
  const submitLabel = isSignData ? lang('Sign') : lang(isSignOnly ? 'Sign' : 'Send');

  const paymentToken = useMemo(() => {
    const slug = paymentOption?.slug;
    return slug ? tokensBySlug[slug] : undefined;
  }, [paymentOption?.slug, tokensBySlug]);

  const paymentAmountText = useMemo(() => {
    if (!paymentOption) {
      return undefined;
    }

    return formatPayOptionAmount(paymentOption);
  }, [paymentOption]);

  const handleBackClick = useLastCallback(() => {
    cancelWalletConnectPay();
  });

  const handlePasswordSubmit = useLastCallback((password: string) => {
    if (isSignData) {
      submitWalletConnectPaySignData({ password });
    } else {
      submitWalletConnectPaySignTransaction({ password });
    }
  });

  const handleClose = useLastCallback(() => {
    closeWalletConnectPay();
  });

  const handleReset = useLastCallback(() => {
    cancelWalletConnectPay();
    updateNextKey();
  });

  useHistoryBack({
    isActive: isOpen && state === WalletConnectPayState.Complete,
    onBack: handleClose,
  });

  useEffect(() => {
    return isOpen && state === WalletConnectPayState.Complete
      ? captureKeyboardListeners({ onEnter: handleClose })
      : undefined;
  }, [isOpen, state, handleClose]);

  function renderPaymentSummary() {
    if (!merchant && !paymentOption) {
      return undefined;
    }

    return (
      <div className={styles.passwordSummary}>
        {merchant && (
          <WalletConnectPayMerchantLogo merchant={merchant} className={styles.passwordMerchantLogoWrap} />
        )}
        {paymentToken && paymentAmountText && merchant?.name && (
          <TransactionBanner
            tokenIn={paymentToken}
            withChainIcon
            text={paymentAmountText}
            className={!getDoesUsePinPad() ? styles.passwordTransactionBanner : undefined}
            secondText={merchant.name}
          />
        )}
      </div>
    );
  }

  function renderPassword(isActive: boolean) {
    return (
      <>
        {!getDoesUsePinPad() && (
          <ModalHeader title={title} onClose={handleClose} />
        )}
        <PasswordForm
          isActive={isActive}
          isLoading={isLoading}
          error={error}
          withCloseButton={getDoesUsePinPad()}
          operationType="transfer"
          submitLabel={submitLabel}
          cancelLabel={lang('Cancel')}
          noAutoConfirm
          noAnimatedIcon
          containerClassName={styles.passwordFormContent}
          onSubmit={handlePasswordSubmit}
          onCancel={handleBackClick}
          onUpdate={clearWalletConnectPayError}
        >
          {renderPaymentSummary()}
        </PasswordForm>
      </>
    );
  }

  function renderResult(isActive: boolean, options: {
    title: string;
    subtitle?: string;
    tgsUrl: string;
    previewUrl: string;
  }) {
    const { title, subtitle, tgsUrl, previewUrl } = options;

    let amountNode;
    if (paymentAmount) {
      const { value, display } = paymentAmount;
      amountNode = (
        <WalletConnectPayAmount
          value={toDecimal(-BigInt(value), display.decimals)}
          decimals={display.decimals}
          suffix={display.assetSymbol}
        />
      );
    }

    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.resultContent)}>
        <WalletConnectPayHeader title={title} subtitle={subtitle} onClose={handleClose} />

        <AnimatedIconWithPreview
          play={isActive}
          noLoop={false}
          nonInteractive
          size={ANIMATED_STICKER_BIG_SIZE_PX}
          className={styles.resultSticker}
          tgsUrl={tgsUrl}
          previewUrl={previewUrl}
        />

        {amountNode}

        {merchant?.name && (
          <div className={styles.resultMerchant}>
            {lang('$transaction_to', {
              address: (
                <span className={styles.resultMerchantTarget}>
                  {merchant.iconUrl && (
                    <img src={merchant.iconUrl} alt="" className={styles.resultMerchantLogo} />
                  )}
                  <span className={styles.resultMerchantName}>{merchant.name}</span>
                </span>
              ),
            })}
          </div>
        )}

        <div className={modalStyles.buttons}>
          <Button isPrimary className={styles.footerButton} onClick={handleClose}>{lang('Close')}</Button>
        </div>
      </div>
    );
  }

  function renderContent(isActive: boolean, isFrom: boolean, currentKey: WalletConnectPayState) {
    switch (currentKey) {
      case WalletConnectPayState.Password:
        return renderPassword(isActive);

      case WalletConnectPayState.Processing:
        return renderResult(isActive, {
          title: lang('Processing Payment'),
          subtitle: lang('It may take a few seconds'),
          tgsUrl: ANIMATED_STICKERS_PATHS.wait,
          previewUrl: ANIMATED_STICKERS_PATHS.waitPreview,
        });

      case WalletConnectPayState.Complete:
        return renderResult(isActive, {
          title: lang('Paid!'),
          tgsUrl: ANIMATED_STICKERS_PATHS.thumbUp,
          previewUrl: ANIMATED_STICKERS_PATHS.thumbUpPreview,
        });
    }
  }

  function resolveModalDialogClassName() {
    switch (state) {
      case WalletConnectPayState.Password:
        return styles.passwordModalDialog;
      case WalletConnectPayState.Processing:
      case WalletConnectPayState.Complete:
        return styles.statusModalDialog;
      default:
        return styles.signModalDialog;
    }
  }

  return (
    <Modal
      hasCloseButton={false}
      isOpen={isOpen}
      dialogClassName={resolveModalDialogClassName()}
      noBackdropClose
      onClose={handleClose}
      onCloseAnimationEnd={handleReset}
    >
      <Transition
        name={resolveSlideTransitionName()}
        className={buildClassName(modalStyles.transition, 'custom-scroll')}
        slideClassName={buildClassName(modalStyles.transitionSlide, styles.modalSlide)}
        activeKey={renderingKey}
        nextKey={nextKey}
      >
        {renderContent}
      </Transition>
    </Modal>
  );
}

function formatPayOptionAmount(option: WcPayPaymentOption): string {
  const { amountValue, display } = option;

  try {
    return formatCurrency(toDecimal(BigInt(amountValue), display.decimals), display.assetSymbol);
  } catch {
    return `${amountValue} ${display.assetSymbol}`;
  }
}

export default memo(withGlobal((global): StateProps => ({
  ...pick(global.currentWalletConnectPay, [
    'state',
    'operation',
    'isLoading',
    'error',
    'merchant',
    'paymentAmount',
    'paymentOption',
    'isSignOnly',
  ]),
  tokensBySlug: global.tokenInfo.bySlug,
}))(WalletConnectPayModal));
