import { useEffect, useMemo } from '../lib/teact/teact';
import { getActions } from '../global';

import type { ApiVestingInfo } from '../api/types';
import type { UserToken } from '../global/types';

import { calcVestingAmountByStatus } from '../util/vesting';
import useLastCallback from './useLastCallback';
import useShowTransition from './useShowTransition';

export default function useVesting(
  { vesting, userMycoin }: {
    vesting?: ApiVestingInfo[];
    userMycoin?: UserToken;
  },
) {
  const { loadMycoin, openVestingModal } = getActions();

  const hasVesting = Boolean(vesting?.length);
  const isMycoinLoaded = Boolean(userMycoin);

  useEffect(() => {
    if (isMycoinLoaded || !hasVesting) return;

    loadMycoin();
  }, [hasVesting, isMycoinLoaded]);

  const amount = useMemo(() => {
    if (!hasVesting) return undefined;

    return calcVestingAmountByStatus(vesting, ['frozen', 'ready']);
  }, [hasVesting, vesting]);

  const unfreezeEndDate = useMemo(() => {
    if (!hasVesting) return undefined;

    for (const { parts } of vesting) {
      for (const part of parts) {
        if (part.status === 'ready') {
          return new Date(part.timeEnd).getTime();
        }
      }
    }

    return undefined;
  }, [hasVesting, vesting]);

  const {
    shouldRender,
    ref,
  } = useShowTransition<HTMLButtonElement>({
    isOpen: Boolean(hasVesting && isMycoinLoaded && userMycoin && amount !== '0'),
    withShouldRender: true,
  });

  const onVestingTokenClick = useLastCallback(() => {
    openVestingModal();
  });

  return {
    shouldRender,
    ref,
    amount,
    vestingStatus: unfreezeEndDate ? 'readyToUnfreeze' as const : 'frozen' as const,
    unfreezeEndDate,
    onVestingTokenClick,
  };
}
