import { createCallbackManager } from '../../util/callbacks';

/**
 * Reports the slugs whose tokens moved to their full slugs and left them to other tokens. A balance stored under such
 * a slug belongs to the previous holder, so the balance streams refetch it.
 */
const slugMoveListeners = createCallbackManager<(slugs: string[]) => void>();

export const onTokenSlugsMove = slugMoveListeners.addCallback;
export const notifyTokenSlugsMove = slugMoveListeners.runCallbacks;
