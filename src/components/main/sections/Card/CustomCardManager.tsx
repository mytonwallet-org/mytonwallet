import React, { memo, useRef } from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';

import useForceUpdate from '../../../../hooks/useForceUpdate';
import useLastCallback from '../../../../hooks/useLastCallback';
import useSyncEffectWithPrevDeps from '../../../../hooks/useSyncEffectWithPrevDeps';

import CustomCardBackground from './CustomCardBackground';

interface OwnProps {
  isSticky?: boolean;
  nft?: ApiNft;
  onCardChange: (hasGradient: boolean, className?: string) => void;
  className?: string;
  shadowClassName?: string;
}

function CustomCardManager({ isSticky, nft, onCardChange, className, shadowClassName }: OwnProps) {
  const prevNftRef = useRef<ApiNft | undefined>(undefined);
  const forceUpdate = useForceUpdate();

  useSyncEffectWithPrevDeps(([prevNft, prevNftAddress]) => {
    if (nft?.address !== prevNftAddress) {
      prevNftRef.current = prevNft;
    }

    if (!nft) {
      onCardChange(false, undefined);
    }
  }, [nft, nft?.address]);

  const prevNft = prevNftRef.current;

  const isMountRef = useRef(true);
  const noShowAnimation = nft && isMountRef.current;
  isMountRef.current = false;

  const handleTransitionEnd = useLastCallback(() => {
    prevNftRef.current = undefined;
    forceUpdate();
  });

  return (
    <div teactFastList>
      {prevNft && (
        <CustomCardBackground
          key={prevNft.address}
          isSticky={isSticky}
          nft={prevNft}
          shouldHide={!nft}
          onTransitionEnd={handleTransitionEnd}
          className={className}
          shadowClassName={shadowClassName}
        />
      )}
      {nft && (
        <CustomCardBackground
          key={nft.address}
          isSticky={isSticky}
          nft={nft}
          noShowAnimation={noShowAnimation}
          onLoad={onCardChange}
          onTransitionEnd={handleTransitionEnd}
          className={className}
          shadowClassName={shadowClassName}
        />
      )}
    </div>
  );
}

export default memo(CustomCardManager);
