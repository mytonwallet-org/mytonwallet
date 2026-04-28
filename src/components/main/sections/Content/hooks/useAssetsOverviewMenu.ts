import { useMemo } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';
import { SettingsState } from '../../../../../global/types';

import { DESKTOP_MIN_ASSETS_TAB_VIEW } from '../../../../../config';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

export type AssetsMenuHandler =
  | 'topMin'
  | 'top10'
  | 'top30'
  | 'addToken'
  | 'manageAssets'
  | 'showCollectibles'
  | 'hide';

export default function useAssetsOverviewMenu({
  selectedAssetsLimit,
  isCollectibleCellVisible,
  canHide,
  hiddenCheckClassName,
}: {
  selectedAssetsLimit?: AssetsMenuHandler;
  isCollectibleCellVisible: boolean;
  canHide: boolean;
  hiddenCheckClassName?: string;
}) {
  const {
    setWalletTokensLimit, openSettingsWithState, setAreCollectiblesHidden, setAreAssetsHidden,
  } = getActions();

  const lang = useLang();

  const menuItems = useMemo<DropdownItem<AssetsMenuHandler>[]>(() => {
    const items: DropdownItem<AssetsMenuHandler>[] = [{
      value: 'topMin',
      name: lang('Top %amount%', { amount: DESKTOP_MIN_ASSETS_TAB_VIEW }) as string,
      fontIcon: 'check',
      fontIconClassName: selectedAssetsLimit === 'topMin' ? undefined : hiddenCheckClassName,
    }, {
      value: 'top10',
      name: lang('Top 10'),
      fontIcon: 'check',
      fontIconClassName: selectedAssetsLimit === 'top10' ? undefined : hiddenCheckClassName,
    }, {
      value: 'top30',
      name: lang('Top 30'),
      fontIcon: 'check',
      fontIconClassName: selectedAssetsLimit === 'top30' ? undefined : hiddenCheckClassName,
    }, {
      value: 'addToken',
      name: lang('Add Token'),
      fontIcon: 'menu-plus',
      withDelimiter: true,
    }, {
      value: 'manageAssets',
      name: lang('Manage Assets'),
      fontIcon: 'menu-params',
    }];

    if (!isCollectibleCellVisible) {
      items.push({
        value: 'showCollectibles',
        name: lang('Show Collectibles'),
        fontIcon: 'eye',
        withDelimiter: true,
      });
    }

    if (canHide) {
      items.push({
        value: 'hide',
        name: lang('Hide Tab'),
        fontIcon: 'eye-closed',
        withDelimiter: isCollectibleCellVisible,
      });
    }

    return items;
  }, [selectedAssetsLimit, isCollectibleCellVisible, canHide, hiddenCheckClassName, lang]);

  const handleMenuItemSelect = useLastCallback((value: AssetsMenuHandler) => {
    switch (value) {
      case 'topMin':
        setWalletTokensLimit({ limit: DESKTOP_MIN_ASSETS_TAB_VIEW });
        break;
      case 'top10':
        setWalletTokensLimit({ limit: 10 });
        break;
      case 'top30':
        setWalletTokensLimit({ limit: 30 });
        break;
      case 'addToken':
        openSettingsWithState({ state: SettingsState.SelectTokenList });
        break;
      case 'manageAssets':
        openSettingsWithState({ state: SettingsState.Assets });
        break;
      case 'showCollectibles':
        setAreCollectiblesHidden({ isHidden: false });
        break;
      case 'hide':
        setAreAssetsHidden({ isHidden: true });
        break;
    }
  });

  return { menuItems, handleMenuItemSelect };
}
