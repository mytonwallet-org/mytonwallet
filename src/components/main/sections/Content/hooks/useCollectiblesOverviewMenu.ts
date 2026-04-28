import { useMemo } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { DropdownItem } from '../../../../ui/Dropdown';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

export type CollectiblesMenuHandler = 'hide' | 'showAssets';

export default function useCollectiblesOverviewMenu({
  canHide,
  isAssetCellVisible,
}: {
  canHide: boolean;
  isAssetCellVisible: boolean;
}) {
  const { setAreCollectiblesHidden, setAreAssetsHidden } = getActions();

  const lang = useLang();

  const menuItems = useMemo<DropdownItem<CollectiblesMenuHandler>[]>(() => {
    const items: DropdownItem<CollectiblesMenuHandler>[] = [];

    if (canHide) {
      items.push({
        value: 'hide',
        name: lang('Hide Tab'),
        fontIcon: 'eye-closed',
      });
    }

    if (!isAssetCellVisible) {
      items.push({
        value: 'showAssets',
        name: lang('Show Assets'),
        fontIcon: 'eye',
        withDelimiter: canHide,
      });
    }

    return items;
  }, [canHide, isAssetCellVisible, lang]);

  const handleMenuItemSelect = useLastCallback((value: CollectiblesMenuHandler) => {
    switch (value) {
      case 'hide':
        setAreCollectiblesHidden({ isHidden: true });
        break;
      case 'showAssets':
        setAreAssetsHidden({ isHidden: false });
        break;
    }
  });

  return { menuItems, handleMenuItemSelect };
}
