import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiStakingState } from '../../../../api/types';
import type { IAnchorPosition, UserToken } from '../../../../global/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { DropdownItem } from '../../../ui/Dropdown';

import { CURRENCIES } from '../../../../config';
import { Big } from '../../../../lib/big.js';
import { selectAccountStakingStates, selectCurrentAccountTokens } from '../../../../global/selectors';
import { formatCurrency, getShortCurrencySymbol } from '../../../../util/formatNumber';
import { calculateFullBalance } from './helpers/calculateFullBalance';

import useLastCallback from '../../../../hooks/useLastCallback';

import DropdownMenu from '../../../ui/DropdownMenu';

interface OwnProps {
  isOpen: boolean;
  excludedCurrency?: string;
  menuPositionX?: 'right' | 'left';
  triggerRef: ElementRef;
  anchor: IAnchorPosition | undefined;
  className?: string;
  onClose: NoneToVoidFunction;
  onChange?: (currency: ApiBaseCurrency) => void;
}

interface StateProps {
  currentCurrency?: ApiBaseCurrency;
  tokens?: UserToken[];
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
}

function CurrencySwitcherMenu({
  isOpen,
  triggerRef,
  anchor,
  currentCurrency,
  excludedCurrency,
  menuPositionX,
  className,
  tokens,
  currencyRates,
  stakingStates,
  onClose,
  onChange,
}: OwnProps & StateProps) {
  const { changeBaseCurrency } = getActions();

  const menuRef = useRef<HTMLDivElement>();

  const currencyList = useMemo<DropdownItem<ApiBaseCurrency>[]>(() => {
    if (!tokens || !currencyRates) {
      return Object.entries(CURRENCIES)
        .filter(([currency]) => currency !== excludedCurrency)
        .map(([currency, { name }]) => ({ value: currency as keyof typeof CURRENCIES, name }));
    }

    const totalBalanceInUsd = new Big(
      calculateFullBalance(tokens, stakingStates).primaryValueUsd,
    );

    return Object.entries(CURRENCIES)
      .filter(([currency]) => currency !== excludedCurrency)
      .map(([currency, { name }]) => {
        const balanceInCurrency = totalBalanceInUsd.mul(currencyRates[currency as ApiBaseCurrency]);

        const currencySymbol = getShortCurrencySymbol(currency as ApiBaseCurrency);
        const formattedBalance = formatCurrency(
          balanceInCurrency.toString(),
          currencySymbol,
          currency === 'BTC' ? 6 : 2,
        );

        return {
          value: currency as keyof typeof CURRENCIES,
          name,
          description: formattedBalance,
        };
      });
  }, [excludedCurrency, tokens, currencyRates, stakingStates]);

  const handleBaseCurrencyChange = useLastCallback((currency: string) => {
    onClose();

    if (currency === currentCurrency) return;

    changeBaseCurrency({ currency: currency as ApiBaseCurrency });
    onChange?.(currency as ApiBaseCurrency);
  });

  const getTriggerElement = useLastCallback(() => triggerRef.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback((): Layout => ({
    withPortal: true,
    centerHorizontally: !menuPositionX,
    preferredPositionX: menuPositionX || 'left' as const,
    doNotCoverTrigger: true,
  }));

  return (
    <DropdownMenu
      withPortal
      ref={menuRef}
      isOpen={isOpen}
      shouldTranslateOptions
      items={currencyList}
      selectedValue={currentCurrency}
      menuPositionX={menuPositionX}
      menuAnchor={anchor}
      getTriggerElement={getTriggerElement}
      getRootElement={getRootElement}
      getMenuElement={getMenuElement}
      getLayout={getLayout}
      className={className}
      onClose={onClose}
      onSelect={handleBaseCurrencyChange}
    />
  );
}

export default memo(withGlobal<OwnProps>((global) => {
  return {
    currentCurrency: global.settings.baseCurrency,
    tokens: selectCurrentAccountTokens(global),
    currencyRates: global.currencyRates,
    stakingStates: selectAccountStakingStates(global, global.currentAccountId!),
  };
})(CurrencySwitcherMenu));
