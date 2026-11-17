import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import { loadChunk } from './helpers/loadChunk';

import useChunk from '../../hooks/useChunk';

interface StateProps {
  isRequested: boolean;
}

/** The trade and receipt modals. They mount once a trade or a receipt opens, so the chunk does not load at startup */
function LazyModals({ isRequested }: StateProps) {
  const chunk = useChunk(loadChunk, isRequested);

  if (!chunk) return undefined;

  return (
    <>
      <chunk.TradeModal />
      <chunk.ActivityModal />
    </>
  );
}

export default memo(withGlobal((global): StateProps => ({
  isRequested: Boolean(global.perps.trade || global.perps.openedActivity),
}))(LazyModals));
