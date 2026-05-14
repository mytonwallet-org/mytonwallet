import { useMemo } from '../../../../../lib/teact/teact';
import { getActions } from '../../../../../global';

import type { ApiChain } from '../../../../../api/types';
import type { OverviewCellSize } from '../../../../../global/types';
import type { DropdownItem } from '../../../../ui/Dropdown';
import { SettingsState } from '../../../../../global/types';

import { DEFAULT_CHAIN } from '../../../../../config';
import buildOverviewCellSizeMenuItems from './buildOverviewCellSizeMenuItems';
import { HIDDEN_NFTS_VALUE } from './useNftCollectionMenuItems';

import useLastCallback from '../../../../../hooks/useLastCallback';

export type CollectiblesMenuHandler =
  | OverviewCellSize
  | 'hide'
  | 'showAssets'
  | typeof HIDDEN_NFTS_VALUE
  | (string & {});

export default function useCollectiblesOverviewMenu({
  overviewCellSize,
  canHide,
  isAssetCellVisible,
  hiddenCheckClassName,
  nftCollectionItems,
  shouldRenderHiddenNftsSection,
}: {
  overviewCellSize?: OverviewCellSize;
  canHide: boolean;
  isAssetCellVisible: boolean;
  hiddenCheckClassName?: string;
  nftCollectionItems: DropdownItem[];
  shouldRenderHiddenNftsSection: boolean;
}) {
  const {
    setOverviewCellSize,
    setAreCollectiblesHidden,
    setAreAssetsHidden,
    openNftCollection,
    openSettingsWithState,
  } = getActions();

  const menuItems = useMemo<DropdownItem<CollectiblesMenuHandler>[]>(() => {
    const items: DropdownItem<CollectiblesMenuHandler>[] = [
      ...buildOverviewCellSizeMenuItems<CollectiblesMenuHandler>(overviewCellSize, hiddenCheckClassName),
    ];

    const nftBlock: DropdownItem<CollectiblesMenuHandler>[] = [...nftCollectionItems];

    if (shouldRenderHiddenNftsSection) {
      nftBlock.push({
        name: 'Hidden NFTs',
        value: HIDDEN_NFTS_VALUE,
        withDelimiter: nftCollectionItems.length > 0,
      });
    }

    if (nftBlock.length) {
      nftBlock[0] = { ...nftBlock[0], withDelimiter: true };
      items.push(...nftBlock);
    }

    if (canHide) {
      items.push({
        value: 'hide',
        name: 'Hide Tab',
        fontIcon: 'eye-closed',
        withDelimiter: true,
      });
    }

    if (!isAssetCellVisible) {
      items.push({
        value: 'showAssets',
        name: 'Show Assets',
        fontIcon: 'eye',
        withDelimiter: !canHide,
      });
    }

    return items;
  }, [
    overviewCellSize, canHide, isAssetCellVisible, hiddenCheckClassName,
    nftCollectionItems, shouldRenderHiddenNftsSection,
  ]);

  const handleMenuItemSelect = useLastCallback((value: CollectiblesMenuHandler) => {
    if (value === 'small' || value === 'medium' || value === 'big') {
      setOverviewCellSize({ size: value as OverviewCellSize });
      return;
    }
    if (value === 'hide') {
      setAreCollectiblesHidden({ isHidden: true });
      return;
    }
    if (value === 'showAssets') {
      setAreAssetsHidden({ isHidden: false });
      return;
    }
    if (value === HIDDEN_NFTS_VALUE) {
      openSettingsWithState({ state: SettingsState.HiddenNfts });
      return;
    }
    if (!value.includes('@')) return;
    const [address, chain] = value.split('@') as [string, ApiChain];
    openNftCollection({ chain: chain || DEFAULT_CHAIN, address }, { forceOnHeavyAnimation: true });
  });

  return { menuItems, handleMenuItemSelect };
}
