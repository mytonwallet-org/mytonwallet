import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useCallback, useEffect, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiBaseCurrency, ApiFetchEstimateDieselResult, ApiNft } from '../../api/types';
import type { SavedAddress, UserToken } from '../../global/types';
import type { LangFn } from '../../hooks/useLang';
import type { ExplainedTransferFee } from '../../util/fee/transferFee';
import type { FeePrecision, FeeTerms } from '../../util/fee/types';
import { ScamWarningType, TransferState } from '../../global/types';

import { DEFAULT_PRICE_CURRENCY, UNKNOWN_TOKEN } from '../../config';
import { getHelpCenterUrl } from '../../global/helpers/getHelpCenterUrl';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentAccountTokenBalance,
  selectCurrentAccountTokens,
  selectIsAllowSuspiciousActions,
  selectIsHardwareAccount,
  selectIsMultichainAccount,
  selectIsMultisigWallet,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';
import { SECOND } from '../../util/dateFormat';
import { stopEvent } from '../../util/domEvents';
import {
  explainApiTransferFee,
  getMaxTransferAmount,
  isBalanceSufficientForTransfer,
} from '../../util/fee/transferFee';
import { vibrate } from '../../util/haptics';
import { isValidAddressOrDomain } from '../../util/isValidAddress';
import { debounce } from '../../util/schedulers';
import { trimStringByMaxBytes } from '../../util/text';
import { getChainBySlug, getIsNativeToken, getIsServiceToken, getNativeToken } from '../../util/tokens';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useFlag from '../../hooks/useFlag';
import useInterval from '../../hooks/useInterval';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { useTransitionActiveKey } from '../../hooks/useTransitionActiveKey';
import { useAmountInputState } from '../ui/hooks/useAmountInputState';

import FeeDetailsModal from '../common/FeeDetailsModal';
import AddressInput from '../ui/AddressInput';
import AmountInput from '../ui/AmountInput';
import Button from '../ui/Button';
import FeeLine from '../ui/FeeLine';
import Modal from '../ui/Modal';
import Transition from '../ui/Transition';
import CommentSection from './CommentSection';
import NftChips from './NftChips';
import NftInfo from './NftInfo';
import SentTabs from './SentTabs';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Transfer.module.scss';

interface OwnProps {
  isStatic?: boolean;
  slideClassName?: string;
}

interface StateProps {
  toAddress?: string;
  resolvedAddress?: string;
  toAddressName?: string;
  amount?: bigint;
  comment?: string;
  shouldEncrypt?: boolean;
  isActive: boolean;
  isLoading?: boolean;
  isComplete?: boolean;
  nativeFee?: bigint;
  realNativeFee?: bigint;
  tokenSlug: string;
  tokens?: UserToken[];
  savedAddresses?: SavedAddress[];
  nativeTokenBalance: bigint;
  isEncryptedCommentSupported: boolean;
  isMemoRequired?: boolean;
  baseCurrency: ApiBaseCurrency;
  nfts?: ApiNft[];
  binPayload?: string;
  stateInit?: string;
  diesel?: ApiFetchEstimateDieselResult;
  isDieselAuthorizationStarted?: boolean;
  isMultichainAccount: boolean;
  isMultisig: boolean;
  isSensitiveDataHidden?: true;
  scamWarningType?: ScamWarningType;
  isAllowSuspiciousActions: boolean;
  isTransferReadonly?: boolean;
}

const COMMENT_MAX_SIZE_BYTES = 5000;
const ACTIVE_STATES = new Set([TransferState.Initial, TransferState.None]);
const AUTHORIZE_DIESEL_INTERVAL_MS = SECOND;

const runDebounce = debounce((cb) => cb(), 500, false);

function TransferInitial({
  isStatic,
  slideClassName,
  tokenSlug,
  toAddress = '',
  resolvedAddress,
  toAddressName = '',
  amount,
  comment = '',
  shouldEncrypt,
  tokens,
  nativeFee,
  realNativeFee,
  savedAddresses,
  nativeTokenBalance,
  isEncryptedCommentSupported,
  isMemoRequired,
  isActive,
  isLoading,
  isComplete,
  baseCurrency,
  nfts,
  binPayload,
  stateInit,
  diesel,
  isDieselAuthorizationStarted,
  isMultichainAccount,
  isMultisig,
  isSensitiveDataHidden,
  scamWarningType,
  isAllowSuspiciousActions,
  isTransferReadonly,
}: OwnProps & StateProps) {
  const {
    submitTransferInitial,
    fetchTransferFee,
    fetchNftFee,
    changeTransferToken,
    setTransferAmount,
    setTransferToAddress,
    setTransferComment,
    setTransferShouldEncrypt,
    cancelTransfer,
    showDialog,
    authorizeDiesel,
    fetchTransferDieselState,
    checkTransferAddress,
    dismissTransferScamWarning,
  } = getActions();

  const isNftTransfer = Boolean(nfts?.length);
  if (isNftTransfer) {
    const nftChain = nfts[0].chain;
    // Token and amount can't be selected in the NFT transfer form, so they are overwritten once for convenience
    tokenSlug = getChainConfig(nftChain).nativeToken.slug;
    amount = undefined;
  }

  const lang = useLang();

  const transferToken = useMemo(() => tokens?.find((token) => token.slug === tokenSlug), [tokenSlug, tokens]);
  const { amount: balance, symbol, chain } = transferToken || {};

  const renderedScamWarningType = useCurrentOrPrev(scamWarningType, true);
  const amountInputRef = useRef<HTMLInputElement>();
  const isDisabledDebounce = useRef<boolean>(false);
  const isAddressValid = chain ? isValidAddressOrDomain(toAddress, chain) : undefined;
  const doesSupportComment = chain && getChainConfig(chain).isTransferPayloadSupported;
  const doesSupportCommentEncryption = !!chain
    && getChainConfig(chain).isEncryptedCommentSupported
    && isEncryptedCommentSupported;
  const transitionKey = useTransitionActiveKey(nfts?.length ? nfts : [tokenSlug]);

  const handleAddressInput = useLastCallback((newToAddress?: string, isValueReplaced?: boolean) => {
    // If value is replaced, callbacks must be executed immediately, without debounce
    if (isValueReplaced) {
      isDisabledDebounce.current = true;
    }

    setTransferToAddress({ toAddress: newToAddress });
  });

  const handleAddressPaste = useLastCallback(() => {
    requestAnimationFrame(() => {
      amountInputRef.current?.focus();
    });
  });

  const shouldDisableClearButton = !toAddress && !(comment || binPayload) && !shouldEncrypt
    && !(isNftTransfer ? isStatic : amount !== undefined);

  const explainedFee = useMemo(
    () => explainApiTransferFee({
      fee: nativeFee, realFee: realNativeFee, diesel, tokenSlug,
    }),
    [nativeFee, realNativeFee, diesel, tokenSlug],
  );

  // Note: this constant has 3 distinct meaningful values
  const isEnoughBalance = isBalanceSufficientForTransfer({
    tokenBalance: balance,
    nativeTokenBalance,
    transferAmount: isNftTransfer ? 0n : amount,
    fullFee: explainedFee.fullFee?.terms,
    canTransferFullBalance: explainedFee.canTransferFullBalance,
  });

  const isAmountMissing = !isNftTransfer && !amount;

  const maxAmount = getMaxTransferAmount({
    tokenBalance: balance,
    tokenSlug,
    fullFee: explainedFee.fullFee?.terms,
    canTransferFullBalance: explainedFee.canTransferFullBalance,
  });

  const isDieselNotAuthorized = diesel?.status === 'not-authorized';
  const authorizeDieselInterval = isDieselNotAuthorized && isDieselAuthorizationStarted
    ? AUTHORIZE_DIESEL_INTERVAL_MS
    : undefined;

  const updateDieselState = useLastCallback(() => {
    fetchTransferDieselState({ tokenSlug });
  });

  useInterval(updateDieselState, authorizeDieselInterval);

  const fullFee = useMemo(() => {
    return getFullFee(explainedFee.fullFee?.terms, tokenSlug);
  }, [explainedFee.fullFee, tokenSlug]);

  useEffect(() => {
    if (
      balance && amount && fullFee !== undefined
      && amount < balance
      && fullFee < balance
      && amount + fullFee >= balance
    ) {
      setTransferAmount({ amount: balance - fullFee });
    }
  }, [amount, balance, fullFee]);

  // Note: this effect doesn't watch amount changes mainly because it's tricky to program a fee recalculation avoidance
  // when the amount changes due to a fee change. And it's not needed because the fee doesn't depend on the amount.
  useEffect(() => {
    if (isAmountMissing || !isAddressValid) {
      return;
    }

    const runFunction = () => {
      if (isNftTransfer) {
        fetchNftFee({
          toAddress,
          comment,
          nfts: nfts ?? [],
        });
      } else {
        fetchTransferFee({
          tokenSlug,
          toAddress,
          amount,
          comment,
          shouldEncrypt,
          binPayload,
          stateInit,
        });
      }
    };

    if (!isDisabledDebounce.current) {
      runDebounce(runFunction);
    } else {
      isDisabledDebounce.current = false;
      runFunction();
    }
  }, [
    isAmountMissing, binPayload, comment, shouldEncrypt, isAddressValid, isNftTransfer, nfts, stateInit, toAddress,
    tokenSlug, amount,
  ]);

  useEffect(() => {
    if (getIsServiceToken(transferToken)) {
      showDialog({
        title: lang('Warning!'),
        message: lang('$service_token_transfer_warning'),
        noBackdropClose: true,
      });
    }
  }, [lang, transferToken]);

  useEffect(() => {
    if (isComplete) clearForm();
  }, [isComplete]);

  const handleTokenChange = useLastCallback((slug: string) => {
    changeTransferToken({ tokenSlug: slug });
  });

  function clearForm() {
    handleAddressInput('');
    checkTransferAddress({});
    setTransferAmount({ amount: undefined });
    setTransferComment({ comment: undefined });
    setTransferShouldEncrypt({ shouldEncrypt: false });
  }

  const handleClear = useLastCallback(() => {
    if (isStatic) {
      cancelTransfer({ shouldReset: true });
    } else {
      clearForm();
    }
  });

  const handleCloseClick = useLastCallback(() => {
    cancelTransfer({ shouldReset: true });
  });

  const handleScamWarningModalClose = useLastCallback(() => {
    dismissTransferScamWarning();

    if (isStatic) {
      clearForm();
    } else {
      cancelTransfer({ shouldReset: true });
    }
  });

  const handleAmountChange = (amount?: bigint, isValueReplaced?: boolean) => {
    // The amount input may change the amount when it's in the base currency mode and the token price changes.
    // Meanwhile, the amount in the global state must not change after the transfer form is submitted.
    if (!isActive) {
      return;
    }

    if (amount !== undefined && amount < 0) {
      return;
    }

    // If the value is replaced, callbacks must be executed immediately, without debounce
    if (isValueReplaced) {
      isDisabledDebounce.current = true;
    }

    setTransferAmount({ amount });
  };

  const handlePaste = useLastCallback(() => {
    isDisabledDebounce.current = true;
  });

  const handleCommentChange = useLastCallback((value) => {
    setTransferComment({ comment: trimStringByMaxBytes(value, COMMENT_MAX_SIZE_BYTES) });
  });

  const isAmountGreaterThanBalance = !isNftTransfer && balance !== undefined && amount !== undefined
    && amount > balance;
  const hasInsufficientFeeError = isEnoughBalance === false && !isAmountGreaterThanBalance
    && diesel?.status !== 'not-authorized' && diesel?.status !== 'pending-previous';
  const hasAmountError = !isNftTransfer && amount !== undefined && (
    (maxAmount !== undefined && amount > maxAmount)
    || hasInsufficientFeeError // Ideally, the insufficient fee error message should be displayed somewhere else
  );
  const isCommentRequired = Boolean(toAddress) && isMemoRequired;
  const hasCommentError = isCommentRequired && !comment;

  const canSubmit = isDieselNotAuthorized || Boolean(
    isAddressValid
    && !isAmountMissing && !hasAmountError
    && isEnoughBalance
    && !hasCommentError
    && !isMultisig
    && (!explainedFee.isGasless || diesel?.status === 'available' || diesel?.status === 'stars-fee')
    && !(isNftTransfer && !nfts?.length),
  );

  const handleSubmit = useLastCallback((e?: React.FormEvent | React.UIEvent) => {
    if (e) stopEvent(e);

    if (scamWarningType) return;

    if (isDieselNotAuthorized) {
      authorizeDiesel();
      return;
    }

    if (!canSubmit) {
      return;
    }

    void vibrate();

    submitTransferInitial({
      tokenSlug,
      amount: amount ?? 0n,
      toAddress,
      comment,
      binPayload,
      shouldEncrypt,
      nfts,
      isGasless: explainedFee.isGasless,
      isGaslessWithStars: diesel?.status === 'stars-fee',
      stateInit,
    });
  });

  const [isFeeModalOpen, openFeeModal, closeFeeModal] = useFeeModal(explainedFee);

  const tokensToSelect = useMemo(
    () => (tokens ?? []).filter((token) => isSelectableToken(token, tokenSlug)),
    [tokens, tokenSlug],
  );

  const amountInputProps = useAmountInputState({
    amount,
    token: transferToken,
    baseCurrency,
    isAmountReadonly: isTransferReadonly,
    onAmountChange: handleAmountChange,
    onTokenChange: handleTokenChange,
  });

  // It is necessary to use useCallback instead of useLastCallback here
  const renderBottomRight = useCallback((className?: string) => {
    let transitionKey = 0;
    let content: TeactNode = ' ';

    if (isMultisig) {
      transitionKey = 1;
      content = <span className={styles.balanceError}>{lang('Multisig sending disabled')}</span>;
    } else if (amount) {
      if (isAmountGreaterThanBalance) {
        transitionKey = 2;
        content = <span className={styles.balanceError}>{lang('Insufficient balance')}</span>;
      } else if (hasInsufficientFeeError) {
        transitionKey = 3;
        content = <span className={styles.balanceError}>{lang('Insufficient fee')}</span>;
      }
    }

    return (
      <Transition
        className={className}
        name="fade"
        activeKey={transitionKey}
      >
        {content}
      </Transition>
    );
  }, [amount, hasInsufficientFeeError, isAmountGreaterThanBalance, isMultisig, lang]);

  function renderButtonText() {
    if (diesel?.status === 'not-authorized') {
      return lang('Authorize %token% Fee', { token: symbol! });
    }
    if (diesel?.status === 'pending-previous') {
      return lang('Awaiting Previous Fee');
    }
    return lang('$send_token_symbol', isNftTransfer ? 'NFT' : symbol || UNKNOWN_TOKEN.symbol);
  }

  function renderFee() {
    let terms: FeeTerms | undefined;
    let precision: FeePrecision = 'exact';

    if (!isAmountMissing) {
      const actualFee = hasInsufficientFeeError ? explainedFee.fullFee : explainedFee.realFee;
      if (actualFee) {
        ({ terms, precision } = actualFee);
      }
    }

    return (
      <FeeLine
        isStatic={isStatic}
        terms={terms}
        token={transferToken}
        precision={precision}
        onDetailsClick={openFeeModal}
      />
    );
  }

  return (
    <>
      <form
        className={isStatic ? undefined : modalStyles.transitionContent}
        onSubmit={handleSubmit}
        onPaste={handlePaste}
      >
        <Transition
          activeKey={transitionKey}
          name="semiFade"
          direction={isStatic && !doesSupportComment ? 'inverse' : undefined}
          shouldCleanup
          slideClassName={buildClassName(styles.formSlide, isStatic && styles.formSlide_static, slideClassName)}
        >
          {!isStatic && (
            <Button
              isRound
              className={buildClassName(modalStyles.closeButton, styles.closeButton)}
              ariaLabel={lang('Close')}
              onClick={handleCloseClick}
            >
              <i className={buildClassName(modalStyles.closeIcon, 'icon-close')} aria-hidden />
            </Button>
          )}
          <SentTabs isInsideModal={!isStatic} />
          {nfts?.length === 1 && <NftInfo nft={nfts[0]} isStatic={isStatic} withMediaViewer />}
          {Boolean(nfts?.length) && nfts.length > 1 && <NftChips nfts={nfts} isStatic={isStatic} />}

          <AddressInput
            label={lang('Recipient Address')}
            value={toAddress}
            chain={chain}
            // NFT transfers are available only on the TON blockchain on this moment
            addressBookChain={chain}
            savedAddresses={savedAddresses}
            validateAddress={checkTransferAddress}
            isStatic={isStatic}
            isReadonly={isTransferReadonly}
            withQrScan
            address={resolvedAddress || toAddress}
            addressName={toAddressName}
            onInput={handleAddressInput}
            onPaste={handleAddressPaste}
            onClose={cancelTransfer}
          />

          {!isNftTransfer && (
            <AmountInput
              {...amountInputProps}
              ref={amountInputRef}
              maxAmount={maxAmount}
              token={transferToken}
              allTokens={tokensToSelect}
              isStatic={isStatic}
              hasError={hasAmountError}
              isMultichainAccount={isMultichainAccount}
              isMaxAmountLoading={maxAmount === undefined}
              isSensitiveDataHidden={isSensitiveDataHidden}
              renderBottomRight={renderBottomRight}
              onPressEnter={handleSubmit}
            />
          )}

          {doesSupportComment && (
            <CommentSection
              comment={comment}
              shouldEncrypt={shouldEncrypt}
              binPayload={binPayload}
              stateInit={stateInit}
              chain={chain}
              isStatic={isStatic}
              isReadonly={isTransferReadonly}
              isCommentRequired={isCommentRequired}
              isEncryptedCommentSupported={doesSupportCommentEncryption}
              onCommentChange={handleCommentChange}
            />
          )}

          <div className={buildClassName(styles.footer, isStatic && !doesSupportComment && styles.footer_shifted)}>
            {renderFee()}

            <div className={styles.buttons}>
              <Button
                isDisabled={shouldDisableClearButton || isLoading}
                className={styles.button}
                onClick={handleClear}
              >
                {lang('Clear')}
              </Button>
              <Button
                isPrimary
                isSubmit
                isDisabled={!canSubmit}
                isLoading={isLoading}
                className={styles.button}
              >
                {renderButtonText()}
              </Button>
            </div>
          </div>
        </Transition>
      </form>
      <FeeDetailsModal
        isOpen={isFeeModalOpen}
        onClose={closeFeeModal}
        fullFee={explainedFee.fullFee?.terms}
        realFee={explainedFee.realFee?.terms}
        realFeePrecision={explainedFee.realFee?.precision}
        excessFee={explainedFee.excessFee}
        excessFeePrecision="approximate"
        token={transferToken}
      />
      <Modal
        isOpen={Boolean(scamWarningType)}
        isCompact
        title={lang('Warning!')}
        noBackdropClose
        onClose={handleScamWarningModalClose}
      >
        <div>
          {getScamWarning(lang, renderedScamWarningType)}
        </div>
        <div className={modalStyles.footerButtons}>
          {isAllowSuspiciousActions ? (
            <>
              <Button
                className={modalStyles.button}
                onClick={handleScamWarningModalClose}
              >
                {lang('Close')}
              </Button>
              <Button
                isPrimary
                isDestructive
                className={modalStyles.button}
                onClick={dismissTransferScamWarning}
              >
                {lang('Continue')}
              </Button>
            </>
          ) : (
            <Button onClick={handleScamWarningModalClose}>{lang('Close')}</Button>
          )}
        </div>
      </Modal>
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const {
        toAddress,
        resolvedAddress,
        toAddressName,
        amount,
        comment,
        shouldEncrypt,
        fee,
        realFee,
        tokenSlug,
        isLoading,
        state,
        nfts,
        binPayload,
        isMemoRequired,
        diesel,
        stateInit,
        scamWarningType,
        isTransferReadonly,
      } = global.currentTransfer;

      const isLedger = selectIsHardwareAccount(global);
      const currentAccountId = selectCurrentAccountId(global)!;
      const accountState = selectCurrentAccountState(global);
      const { baseCurrency = DEFAULT_PRICE_CURRENCY, isSensitiveDataHidden } = global.settings;
      const isActive = ACTIVE_STATES.has(state);

      const chain = getChainBySlug(tokenSlug);
      return {
        toAddress,
        resolvedAddress,
        toAddressName,
        amount,
        comment,
        shouldEncrypt,
        nativeFee: fee,
        realNativeFee: realFee,
        nfts,
        tokenSlug,
        binPayload,
        stateInit,
        tokens: selectCurrentAccountTokens(global),
        savedAddresses: accountState?.savedAddresses,
        isEncryptedCommentSupported: !isLedger && !nfts?.length && !isMemoRequired,
        isMemoRequired,
        isActive,
        isLoading: isLoading && isActive,
        isComplete: state === TransferState.Complete,
        baseCurrency,
        nativeTokenBalance: selectCurrentAccountTokenBalance(global, getNativeToken(chain).slug),
        diesel,
        isDieselAuthorizationStarted: accountState?.isDieselAuthorizationStarted,
        isMultichainAccount: selectIsMultichainAccount(global, currentAccountId),
        isMultisig: selectIsMultisigWallet(global, currentAccountId, chain),
        isSensitiveDataHidden,
        scamWarningType,
        isAllowSuspiciousActions: selectIsAllowSuspiciousActions(global, currentAccountId),
        isTransferReadonly,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(TransferInitial),
);

function useFeeModal(explainedFee: ExplainedTransferFee) {
  const isAvailable = explainedFee.realFee?.precision !== 'exact';
  const [isOpen, open, close] = useFlag(false);
  const openIfAvailable = isAvailable ? open : undefined;
  return [isOpen, openIfAvailable, close] as const;
}

function isSelectableToken(token: UserToken, selectedTokenSlug: string) {
  return token.type !== 'lp_token'
    || (token.amount > 0 && !token.isDisabled)
    || token.slug === selectedTokenSlug;
}

function getScamWarning(lang: LangFn, scamWarning: ScamWarningType | undefined) {
  if (!scamWarning) return undefined;

  return lang(scamWarning === ScamWarningType.DomainLike
    ? '$domain_like_scam_warning'
    : '$seed_phrase_scam_warning', {
    help_center_link: (
      <a
        href={getHelpCenterUrl(lang.code, scamWarning === ScamWarningType.DomainLike ? 'domainScam' : 'seedScam')}
        target="_blank"
        rel="noreferrer"
      >
        <b>{lang('$help_center_prepositional')}</b>
      </a>
    ),
  });
}

// Calculates fee in the token currency to keep abstraction from SDK native fee values
function getFullFee(terms: FeeTerms<bigint> | undefined, tokenSlug: string): bigint | undefined {
  if (!terms) return undefined;
  const tokenPart = terms.token ?? 0n;
  const nativePart = getIsNativeToken(tokenSlug) ? (terms.native ?? 0n) : 0n;
  return tokenPart + nativePart;
}
