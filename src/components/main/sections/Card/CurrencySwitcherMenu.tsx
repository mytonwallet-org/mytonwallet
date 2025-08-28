import type { ElementRef } from '../../../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency } from '../../../../api/types';
import type { Layout } from '../../../../hooks/useMenuPosition';
import type { IAnchorPosition } from '../../../../types';
import type { DropdownItem } from '../../../ui/Dropdown';

import { CURRENCIES } from '../../../../config';

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
}

function CurrencySwitcherMenu({
  isOpen,
  triggerRef,
  anchor,
  currentCurrency,
  excludedCurrency,
  menuPositionX,
  className,
  onClose,
  onChange,
}: OwnProps & StateProps) {
  const { changeBaseCurrency } = getActions();

  const menuRef = useRef<HTMLDivElement>();

  const currencyList = useMemo<DropdownItem<ApiBaseCurrency>[]>(
    () => Object.entries(CURRENCIES)
      .filter(([currency]) => currency !== excludedCurrency)
      .map(([currency, { name }]) => ({ value: currency as keyof typeof CURRENCIES, name })),
    [excludedCurrency],
  );

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
      items={currencyList}
      shouldTranslateOptions
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
  };
})(CurrencySwitcherMenu));
