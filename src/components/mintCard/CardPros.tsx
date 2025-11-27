import React, { memo } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiMtwCardType } from '../../api/types';

import { DEFAULT_FEE, TONCOIN } from '../../config';
import buildClassName from '../../util/buildClassName';
import { fromDecimal } from '../../util/decimals';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';

import styles from './CardPros.module.scss';

interface OwnProps {
  type: ApiMtwCardType;
  price?: number;
  balance?: bigint;
  isAvailable?: boolean;
}

function CardPros({ type, price, balance, isAvailable }: OwnProps) {
  const { startCardMinting, showDialog } = getActions();

  const lang = useLang();
  const isEnoughBalance = price && balance ? fromDecimal(price, TONCOIN.decimals) + DEFAULT_FEE < balance : false;

  const handleSubmit = useLastCallback(() => {
    if (!isEnoughBalance) {
      showDialog({
        title: lang('Insufficient Balance'),
        message: lang('Please top up your %token% balance.', { token: TONCOIN.symbol }),
      });

      return;
    }

    startCardMinting({ type });
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
          isDisabled={!isAvailable}
          className={styles.button}
          onClick={handleSubmit}
        >
          {lang('Upgrade for %currency% %amount%', {
            amount: price,
            currency: <i className={buildClassName(styles.currencyIcon, 'icon-ton')} aria-label="TON" />,
          })}
        </Button>
      )}
    </div>
  );
}

export default memo(CardPros);
