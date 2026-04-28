import { useMemo } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { ApiNftCollection } from '../../../../../api/types';
import type { DropdownItem } from '../../../../ui/Dropdown';

import useLang from '../../../../../hooks/useLang';
import useLastCallback from '../../../../../hooks/useLastCallback';

export type CollectionMenuHandler = 'hide' | 'showAssets' | 'showCollectibles';

export default function useCollectionOverviewMenu({
  canHide,
  isAssetCellVisible,
  isCollectibleCellVisible,
}: {
  canHide: boolean;
  isAssetCellVisible: boolean;
  isCollectibleCellVisible: boolean;
}) {
  const { removeCollectionTab, setAreAssetsHidden, setAreCollectiblesHidden } = getActions();

  const lang = useLang();

  const menuItems = useMemo<DropdownItem<CollectionMenuHandler>[]>(() => {
    const items: DropdownItem<CollectionMenuHandler>[] = [{
      value: 'hide',
      name: lang('Hide Tab'),
      fontIcon: 'eye-closed',
      isDisabled: !canHide,
    }];

    if (!isAssetCellVisible) {
      items.push({
        value: 'showAssets',
        name: lang('Show Assets'),
        fontIcon: 'eye',
        withDelimiter: true,
      });
    }

    if (!isCollectibleCellVisible) {
      items.push({
        value: 'showCollectibles',
        name: lang('Show Collectibles'),
        fontIcon: 'eye',
        withDelimiter: isAssetCellVisible,
      });
    }
    return items;
  }, [canHide, isAssetCellVisible, isCollectibleCellVisible, lang]);

  const handleMenuItemSelect = useLastCallback((
    value: CollectionMenuHandler,
    collection: ApiNftCollection,
  ) => {
    switch (value) {
      case 'hide':
        removeCollectionTab({ collection });
        break;
      case 'showAssets':
        setAreAssetsHidden({ isHidden: false });
        break;
      case 'showCollectibles':
        setAreCollectiblesHidden({ isHidden: false });
        break;
    }
  });

  return { menuItems, handleMenuItemSelect };
}
