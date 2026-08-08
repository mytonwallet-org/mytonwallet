import type { getActions } from '../index';
import type { GlobalState } from '../types';

type Actions = ReturnType<typeof getActions>;

type AsyncActionHandler<Payload> = (global: GlobalState, actions: Actions, payload: Payload) => Promise<void>;

/**
 * How many flows are still reading with a given token. One password entry can serve more than one -
 * the multichain upgrade runs alongside the operation the user actually asked for - so the one that
 * finishes first must not take the session out from under the other.
 */
const holdersByToken = new Map<string, number>();

/**
 * For a flow that reads with someone else's token and cannot be wrapped, because whether it runs at
 * all is decided inside the handler: taking the hold unconditionally would let it be taken and given
 * back before the operation it rides along with has started.
 */
export function holdEnclaveSession(token: string) {
  holdersByToken.set(token, (holdersByToken.get(token) ?? 0) + 1);
}

/** Whether that was the last flow reading with this token. */
export function dropEnclaveSessionHold(token: string) {
  const holders = (holdersByToken.get(token) ?? 1) - 1;
  if (holders > 0) {
    holdersByToken.set(token, holders);
    return false;
  }

  holdersByToken.delete(token);
  return true;
}

/**
 * Wraps an operation that authorizes so the secret reads it does not take are given back once the
 * last flow on that session is done, however it ended. A flow has to name its budget before it
 * starts and can only name the largest it might need, an operation that fails before it signs takes
 * none of what it was given, and a usage-counted session has no expiry of its own - so anything left
 * over stays a live permission to read the private key.
 *
 * For flows that end where the handler ends. A step that hands its token to a later step must not be
 * wrapped: by the time the later step runs, this one has already let go and the session is gone.
 */
export function withEnclaveSessionRelease<Payload extends { enclaveToken?: string } | undefined>(
  handler: AsyncActionHandler<Payload>,
): AsyncActionHandler<Payload> {
  return async (global, actions, payload) => {
    const enclaveToken = payload?.enclaveToken;
    if (enclaveToken) {
      holdEnclaveSession(enclaveToken);
    }

    try {
      await handler(global, actions, payload);
    } finally {
      if (enclaveToken && dropEnclaveSessionHold(enclaveToken)) {
        actions.releaseEnclaveSession({ enclaveToken });
      }
    }
  };
}
