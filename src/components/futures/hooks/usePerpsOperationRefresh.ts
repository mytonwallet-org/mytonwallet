import { getActions } from '../../../global';

import type { ApiPerpsOperation } from '../../../api/types';

import { isPerpsOperationBlocking } from '../../../global/selectors';
import { SECOND } from '../../../util/dateFormat';

import useInterval from '../../../hooks/useInterval';
import useIsInForeground from '../../../hooks/useIsInForeground';
import useLastCallback from '../../../hooks/useLastCallback';

const REFRESH_INTERVAL = 5 * SECOND;

/**
 * Follows an operation on its status or receipt screen, as on iOS: every 5 seconds, it reads unfinished operations
 * back from the SDK and reloads the positions and the history, which bring the fill of the operation. It stops once
 * the operation is resolved and the fill of its order is known. The returned function refreshes once more, for the
 * Refresh button.
 */
export default function usePerpsOperationRefresh(operation?: ApiPerpsOperation, hasFill?: boolean) {
  const { reconcilePerpsOperations, loadPerpsSnapshot, loadPerpsHistory } = getActions();

  const isInForeground = useIsInForeground();
  // A completed order waits for its fill. A change of the leverage and a withdrawal from the balance place no order, so
  // they never get one.
  const isWatched = operation !== undefined && (
    isPerpsOperationBlocking(operation)
    || (operation.state === 'completed' && operation.orderId !== undefined && operation.kind !== 'leverage' && !hasFill)
  );

  const refresh = useLastCallback(() => {
    reconcilePerpsOperations();
    loadPerpsSnapshot();
    loadPerpsHistory();
  });

  useInterval(refresh, isWatched && isInForeground ? REFRESH_INTERVAL : undefined, true);

  return refresh;
}
