import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiToken } from '../../api/types';
import type {
  Account, GlobalState, SavedAddress, UserToken,
} from '../../global/types';

import {
  ANIMATED_STICKER_SMALL_SIZE_PX,
  BURN_ADDRESS,
  BURN_CHUNK_DURATION_APPROX_SEC,
  NFT_BATCH_SIZE,
  NOTCOIN_EXCHANGERS,
  STARS_SYMBOL,
} from '../../config';
import renderText from '../../global/helpers/renderText';
import { selectCurrentAccountId, selectNetworkAccounts } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig, getChainTitle } from '../../util/chain';
import { toDecimal } from '../../util/decimals';
import { explainApiTransferFee } from '../../util/fee/transferFee';
import { getLocalAddressName } from '../../util/getLocalAddressName';
import { vibrate } from '../../util/haptics';
import { getChainBySlug } from '../../util/tokens';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AmountWithFeeTextField from '../ui/AmountWithFeeTextField';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Fee from '../ui/Fee';
import IconWithTooltip from '../ui/IconWithTooltip';
import InteractiveTextField from '../ui/InteractiveTextField';
import ModalHeader from '../ui/ModalHeader';
import NftChips from './NftChips';
import NftInfo from './NftInfo';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Transfer.module.scss';

interface OwnProps {
  isActive: boolean;
  savedAddresses?: SavedAddress[];
  token?: UserToken | ApiToken;
  onBack: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  currentAccountId: string;
  currentTransfer: GlobalState['currentTransfer'];
  accounts?: Record<string, Account>;
}

function TransferConfirm({
  currentTransfer: {
    tokenSlug,
    amount,
    toAddress,
    resolvedAddress,
    fee,
    realFee,
    comment,
    shouldEncrypt,
    promiseId,
    isLoading,
    toAddressName,
    isToNewAddress,
    isScam,
    binPayload,
    nfts,
    isGaslessWithStars,
    diesel,
    stateInit,
    isOfframp,
    isNftBurn,
  },
  token,
  currentAccountId,
  accounts,
  isActive,
  savedAddresses,
  onBack,
  onClose,
}: OwnProps & StateProps) {
  const { submitTransferConfirm } = getActions();

  const lang = useLang();

  const isNftTransfer = Boolean(nfts?.length);
  if (isNftTransfer) {
    const nftChain = nfts[0].chain;
    tokenSlug = getChainConfig(nftChain).nativeToken.slug;
  }

  const chain = getChainBySlug(tokenSlug);
  const localAddressName = useMemo(() => getLocalAddressName({
    address: toAddress!,
    chain,
    currentAccountId,
    accounts: accounts!,
    savedAddresses,
  }), [accounts, chain, currentAccountId, savedAddresses, toAddress]);
  const addressName = localAddressName || toAddressName;
  const isBurning = resolvedAddress === BURN_ADDRESS || isNftBurn;
  const isNotcoinBurning = resolvedAddress === NOTCOIN_EXCHANGERS[0];
  const explainedFee = explainApiTransferFee({
    fee,
    realFee,
    diesel,
    tokenSlug,
  });

  useHistoryBack({
    isActive,
    onBack,
  });

  const handleConfirm = useLastCallback(() => {
    void vibrate();
    submitTransferConfirm();
  });

  function renderNfts() {
    if (nfts!.length === 1) {
      return <NftInfo nft={nfts![0]} withMediaViewer />;
    }

    return <NftChips nfts={nfts!} />;
  }

  function renderAmountWithFee() {
    if (!explainedFee.realFee || !token) {
      return undefined;
    }

    const feeText = (
      <Fee
        terms={explainedFee.realFee.terms}
        precision={explainedFee.realFee.precision}
        token={token}
        symbolClassName={styles.currencySymbol}
      />
    );

    return isNftTransfer ? (
      <>
        <div className={styles.label}>{lang('Fee')}</div>
        <div className={styles.inputReadOnly}>{feeText}</div>
      </>
    ) : (
      <AmountWithFeeTextField
        label={lang('Amount')}
        amount={toDecimal(amount ?? 0n, token?.decimals)}
        symbol={token?.symbol ?? ''}
        feeText={feeText}
        fractionDigits={token?.decimals}
      />
    );
  }

  function renderComment() {
    if (binPayload || stateInit) {
      return (
        <>
          {binPayload && (
            <>
              <div className={styles.label}>{lang('Signing Data')}</div>
              <InteractiveTextField
                text={binPayload}
                copyNotification={lang('Data Copied')}
                className={styles.addressWidget}
              />
            </>
          )}

          {stateInit && (
            <>
              <div className={styles.label}>{lang('Contract Initialization Data')}</div>
              <InteractiveTextField
                text={stateInit}
                copyNotification={lang('Data Copied')}
                className={styles.addressWidget}
              />
            </>
          )}

          <div className={styles.error}>
            {renderText(lang('$signature_warning'))}
          </div>
        </>
      );
    }

    if (!comment) {
      return undefined;
    }

    return (
      <>
        <div className={styles.label}>{shouldEncrypt ? lang('Encrypted Message') : lang('Comment or Memo')}</div>
        <div className={buildClassName(styles.inputReadOnly, styles.inputReadOnly_words, styles.commentInputWrapper)}>
          {comment}
        </div>
      </>
    );
  }

  const burningDurationMin = nfts?.length
    ? (Math.ceil(nfts.length / NFT_BATCH_SIZE) * BURN_CHUNK_DURATION_APPROX_SEC) / 60
    : undefined;

  function getSubmitBtnText() {
    if (isOfframp) {
      return lang('Sell %symbol%', { symbol: token?.symbol ?? '' });
    }
    if (isBurning || isNotcoinBurning) {
      return lang(isNftTransfer ? 'Burn NFT' : 'Burn');
    }
    if (isGaslessWithStars) {
      return lang('Pay fee with %stars_symbol%', { stars_symbol: STARS_SYMBOL });
    }
    return lang('Confirm');
  }

  return (
    <>
      <ModalHeader title={lang('Is it all ok?')} onClose={onClose} />
      <div className={modalStyles.transitionContent}>
        {isNftTransfer ? renderNfts() : (
          <AnimatedIconWithPreview
            size={ANIMATED_STICKER_SMALL_SIZE_PX}
            play={isActive}
            noLoop={false}
            nonInteractive
            className={buildClassName(styles.sticker, styles.sticker_sizeSmall)}
            tgsUrl={ANIMATED_STICKERS_PATHS.bill}
            previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
          />
        )}
        {!isNftBurn && (
          <>
            <div className={styles.label}>
              {lang('Receiving Address')}
              {' '}
              {isToNewAddress && (
                <IconWithTooltip
                  emoji="⚠️"
                  size="small"
                  message={lang('This address is new and never received transfers before.')}
                  tooltipClassName={styles.warningTooltipContainer}
                />
              )}
            </div>
            <InteractiveTextField
              chain={chain}
              address={resolvedAddress}
              addressName={addressName}
              isScam={isScam}
              copyNotification={lang('%chain% Address Copied', { chain: getChainTitle(chain) }) as string}
              className={styles.addressWidget}
              forceFullAddress
            />
          </>
        )}
        {renderAmountWithFee()}
        {renderComment()}

        {nfts && (isBurning || (isNotcoinBurning && nfts?.length > 1)) && (
          <div className={styles.burnWarning}>
            {(
              nfts?.length === 1 ? (
                renderText(lang('Are you sure you want to burn this NFT? It will be lost forever.'))
              ) : ([
                renderText(lang('$multi_burn_nft_warning', { amount: nfts.length })),
                ' ',
                renderText(lang('$multi_send_nft_warning', { duration: burningDurationMin })),
              ])
            )}
          </div>
        )}

        <div className={buildClassName(modalStyles.buttons, modalStyles.buttonsInsideContentWithScroll)}>
          {!isOfframp && (
            <Button className={modalStyles.button} onClick={promiseId ? onClose : onBack}>
              {promiseId ? lang('Cancel') : lang('Edit')}
            </Button>
          )}
          <Button
            isPrimary
            isLoading={isLoading}
            isDestructive={isBurning || isScam}
            className={modalStyles.button}
            onClick={handleConfirm}
          >
            {getSubmitBtnText()}
          </Button>
        </div>
      </div>
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    currentAccountId: selectCurrentAccountId(global)!,
    currentTransfer: global.currentTransfer,
    accounts: selectNetworkAccounts(global),
  };
})(TransferConfirm));
