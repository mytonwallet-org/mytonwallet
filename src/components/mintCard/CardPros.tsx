import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiMtwCardType, ApiTokenWithPrice } from '../../api/types';

import { TONCOIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { fromDecimal, toDecimal } from '../../util/decimals';
import { getToncoinAmountForTransfer } from '../../util/fee/getTonOperationFees';
import { formatNumber } from '../../util/formatNumber';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';

import styles from './CardPros.module.scss';

interface OwnProps {
  type: ApiMtwCardType;
  mycoin?: ApiTokenWithPrice;
  price?: number;
  mycoinBalance?: bigint;
  toncoinBalance?: bigint;
  isAvailable?: boolean;
}

const SWAP_AMOUNT_RESERVE_MULTIPLIER = 105n; // 100% + 5% reserve

function CardPros({ type, mycoin, price, mycoinBalance, toncoinBalance, isAvailable }: OwnProps) {
  const { startCardMinting, showDialog, startSwap, setSwapAmountOut, closeMintCardModal } = getActions();

  const lang = useLang();
  const isEnoughMycoinBalance = price && mycoinBalance && mycoin
    ? fromDecimal(price, mycoin.decimals) <= mycoinBalance
    : false;

  // Calculate required TON for token transfer: base transfer amount + network fee
  const requiredToncoinForFee = mycoin ? getToncoinAmountForTransfer(mycoin, false).amountWithDefaultFee : 0n;
  const isEnoughToncoinBalance = toncoinBalance ? requiredToncoinForFee <= toncoinBalance : false;
  const isSubmitDisabled = !isAvailable || !mycoin;

  const handleSubmit = useLastCallback(() => {
    if (isEnoughMycoinBalance && isEnoughToncoinBalance) {
      startCardMinting({ type });

      return;
    }

    if (!isEnoughMycoinBalance) {
      if (!mycoin || !price) {
        return;
      }

      const requiredAmount = fromDecimal(price, mycoin.decimals);
      const missingAmount = mycoinBalance
        ? requiredAmount - mycoinBalance
        : requiredAmount;

      const missingAmountWithReserve = missingAmount * SWAP_AMOUNT_RESERVE_MULTIPLIER / 100n;
      const missingAmountDecimal = toDecimal(missingAmountWithReserve, mycoin.decimals);
      closeMintCardModal();
      startSwap({
        tokenInSlug: TONCOIN.slug,
        tokenOutSlug: mycoin.slug,
      });
      setSwapAmountOut({ amount: missingAmountDecimal });
      return;
    }

    showDialog({
      title: lang('Insufficient Fee'),
      message: lang('Please top up your %token% balance.', { token: TONCOIN.symbol }),
    });
    return;
  });

  return (
    <div className={buildClassName(styles.root, styles[type])}>
      <dl className={styles.list}>
        <dt className={styles.term}>
          {lang('Unique')}
          <i className={buildClassName(styles.icon, 'icon-diamond')} aria-hidden />
        </dt>
        <dd className={styles.data}>
          {lang('Get a card with unique background and personalized palette for wallet interface.')}
        </dd>

        <dt className={styles.term}>
          {lang('Transferable')}
          <i className={buildClassName(styles.icon, 'icon-swap')} aria-hidden />
        </dt>
        <dd className={styles.data}>{lang('Easily send your upgraded card to any of your friends.')}</dd>

        <dt className={styles.term}>
          {lang('Tradable')}
          <i className={buildClassName(styles.icon, 'icon-auction')} aria-hidden />
        </dt>
        <dd className={styles.data}>{lang('Sell or auction your card on third-party NFT marketplaces.')}</dd>
      </dl>

      {!!price && (
        <Button
          isPrimary
          isDisabled={isSubmitDisabled}
          className={styles.button}
          onClick={isSubmitDisabled ? undefined : handleSubmit}
        >
          {lang('Upgrade for %amount% %currency%', {
            amount: formatNumber(price),
            currency: mycoin?.symbol || 'MY',
          })}
        </Button>
      )}
    </div>
  );
}

export default memo(CardPros);
