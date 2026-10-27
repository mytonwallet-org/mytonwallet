import React, { memo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiInfoBannerPromotion } from '../../../../api/types';

import { ANIMATION_LEVEL_MIN, TONCOIN } from '../../../../config';
import { selectCurrentAccountHomeBanners, selectCurrentAccountId } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import useHeightChange from '../../../../hooks/useHeightChange';
import useLastCallback from '../../../../hooks/useLastCallback';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import InfoBanner from '../../../common/InfoBanner';

import styles from './HomeBanners.module.scss';

interface OwnProps {
  onHeightChange: (prevHeight: number, nextHeight: number) => void;
}

interface StateProps {
  accountId?: string;
  banners?: ApiInfoBannerPromotion[];
  isSensitiveDataHidden?: true;
  noAnimation: boolean;
}

// Matches the closing transition in `HomeBanners.module.scss`
const CLOSE_DURATION = 300;

function HomeBanners({
  accountId,
  banners,
  isSensitiveDataHidden,
  noAnimation,
  onHeightChange,
}: OwnProps & StateProps) {
  const { startStaking, dismissHomeBanner } = getActions();

  const ref = useRef<HTMLDivElement>();
  const [closingId, setClosingId] = useState<string>();
  const [grownId, setGrownId] = useState<string>();

  // Banner ids repeat across accounts, and with the landscape Agent open this component stays mounted when
  // the account changes. Without the reset, a banner closed on one account would stay hidden on the next one.
  useSyncEffect(() => {
    setClosingId(undefined);
    setGrownId(undefined);
  }, [accountId]);

  const frontBanner = banners?.[0];
  const nextBanner = banners?.[1];
  const isClosing = frontBanner !== undefined && frontBanner.id === closingId;

  // The grown edge stays under the card that has just replaced the closed one, so only its content fades in
  const isGrownFront = frontBanner !== undefined && frontBanner.id === grownId && !isClosing;
  const shouldRenderEdge = Boolean(nextBanner) || isGrownFront;
  const isEdgeGrown = isClosing || (isGrownFront && !nextBanner);

  useHeightChange(ref, onHeightChange);

  const handleActionClick = useLastCallback(() => {
    // Parity with the iOS app, which also opens staking by the TON slug
    startStaking({ tokenSlug: TONCOIN.slug });
  });

  const handleClose = useLastCallback((id: string) => {
    setClosingId(id);
    setGrownId(nextBanner?.id);

    setTimeout(() => {
      dismissHomeBanner({ accountId: accountId!, id });
    }, noAnimation ? 0 : CLOSE_DURATION);
  });

  return (
    <div ref={ref} className={buildClassName(styles.root, frontBanner && styles.rootFilled)}>
      {shouldRenderEdge && (
        <div key="edge" className={buildClassName(styles.edge, isEdgeGrown && styles.edgeGrown)} />
      )}
      {frontBanner && (
        <InfoBanner
          key={frontBanner.id}
          banner={frontBanner}
          isSensitiveDataHidden={isSensitiveDataHidden}
          className={buildClassName(styles.banner, isClosing && styles.bannerClosing)}
          onActionClick={handleActionClick}
          onClose={handleClose}
        />
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    accountId: selectCurrentAccountId(global),
    banners: selectCurrentAccountHomeBanners(global),
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
    noAnimation: global.settings.animationLevel === ANIMATION_LEVEL_MIN,
  };
})(HomeBanners));
