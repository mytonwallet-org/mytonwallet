import { getActions } from '../../../../../global';

import type { ApiNftCollection } from '../../../../../api/types';
import { ContentTab } from '../../../../../global/types';

import useLastCallback from '../../../../../hooks/useLastCallback';

export default function useWalletOverview() {
  const { setActiveContentTab, showTokenActivity, openNftCollection } = getActions();

  const handleTokenClick = useLastCallback((slug: string) => {
    showTokenActivity({ slug, returnTab: ContentTab.Overview });
  });

  const handleShowAllAssets = useLastCallback(() => {
    setActiveContentTab({ tab: ContentTab.Assets });
  });

  const handleShowAllNfts = useLastCallback(() => {
    setActiveContentTab({ tab: ContentTab.Nft });
  });

  const handleShowCollection = useLastCallback((collection: ApiNftCollection) => {
    openNftCollection({ address: collection.address, chain: collection.chain });
  });

  return {
    handleTokenClick,
    handleShowAllAssets,
    handleShowAllNfts,
    handleShowCollection,
  };
}
