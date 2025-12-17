import React, { memo } from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { UserToken } from '../../global/types';

import { DEFAULT_CARD_ADDRESS } from './constants';

import useLastCallback from '../../hooks/useLastCallback';

import NftCardItem from './NftCardItem';

import styles from './CardGrid.module.scss';

interface OwnProps {
  cards: ApiNft[];
  selectedAddress?: string;
  onCardSelect: (address: string) => void;
  tokens?: UserToken[];
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
}

function CardGrid({
  cards, selectedAddress, onCardSelect, tokens, baseCurrency, currencyRates,
}: OwnProps) {
  const handleCardClick = useLastCallback((address: string) => {
    onCardSelect(address);
  });

  return (
    <div className={styles.grid}>
      <NftCardItem
        key="default"
        isSelected={selectedAddress === DEFAULT_CARD_ADDRESS}
        tokens={tokens}
        baseCurrency={baseCurrency}
        currencyRates={currencyRates}
        onClick={handleCardClick}
      />
      {cards.map((card) => (
        <NftCardItem
          key={card.address}
          card={card}
          isSelected={card.address === selectedAddress}
          tokens={tokens}
          baseCurrency={baseCurrency}
          currencyRates={currencyRates}
          onClick={handleCardClick}
        />
      ))}
    </div>
  );
}

export default memo(CardGrid);
