import type {
  ApiAccountAny,
  ApiPerpsAccountPosition,
  ApiPerpsAccountSnapshot,
  ApiPerpsGetPositionsResult,
  ApiPerpsListedAsset,
  OnApiUpdate,
} from '../types';

import { Big } from '../../lib/big.js';
import { parseAccountId } from '../../util/account';
import { areDeepEqual } from '../../util/areDeepEqual';
import { logDebugError } from '../../util/logs';
import { doesAccountHaveChain } from '../common/accounts';
import { buildPerpsMarketCatalogue } from '../common/perpsMarket';
import { getPerpsBalanceWithdrawalPreview, normalizePerpsPosition } from '../common/perpsPresentation';
import { pollingLoop } from '../common/polling/utils';
import { MINUTE, SEC } from '../constants';
import { getEnvironment } from '../environment';
import { getPerpsWallet, perpsGetAssets, perpsGetPositions } from './perps';

/** Open positions change with every price move; while the app is idle they are read rarely. */
const POSITIONS_INTERVAL = { focused: 20 * SEC, notFocused: 5 * MINUTE };
const POSITIONS_MIN_DELAY = { focused: 2 * SEC, notFocused: 10 * SEC };
const POSITIONS_UNAVAILABLE_AFTER = MINUTE;

let onUpdate: OnApiUpdate | undefined;
let activePolling: { accountId: string; poll: NoneToVoidFunction } | undefined;
const lastPublished = new Map<string, Omit<ApiPerpsAccountSnapshot, 'timestamp'>>();
let readSequence = 0;
/** The answered read that started last, per account. An earlier read that answers after it must not overwrite it. */
const newestReads = new Map<string, { sequence: number; snapshot: ApiPerpsAccountSnapshot }>();

export function initPerpsPositions(update: OnApiUpdate) {
  onUpdate = update;
}

export function getPerpsPositionsState(result: ApiPerpsGetPositionsResult) {
  const state = result.positionsByChain.hyperliquid;
  if (!state) throw new Error('PerpsIncompleteData');
  return state;
}

/**
 * Reads positions after resolving the wallet, while `loadAssets` resolves the catalogue they are matched against.
 * A position whose market is missing from the catalogue makes its book unavailable instead of being dropped silently.
 */
export async function getPerpsAccountSnapshot(
  accountId: string,
  loadAssets: () => Promise<ApiPerpsListedAsset[]>,
): Promise<ApiPerpsAccountSnapshot> {
  const { address, tradingAvailability } = await getPerpsWallet(accountId);
  const [assets, result] = await Promise.all([
    loadAssets(),
    perpsGetPositions({ addressByChain: { hyperliquid: address } }),
  ]);
  const state = getPerpsPositionsState(result);
  const unavailableDexs: string[] = [];
  const positions: ApiPerpsAccountPosition[] = [];
  for (const { position } of state.assetPositions) {
    if (Big(position.szi).eq(0)) continue;
    const asset = assets.find((value) => value.name === position.coin);
    if (!asset) {
      unavailableDexs.push(position.coin.includes(':') ? position.coin.split(':')[0] : '');
      continue;
    }
    positions.push(normalizePerpsPosition(accountId, asset, position));
  }
  const unique = [...new Map(positions.map((p) => [p.id, p])).values()].sort((a, b) =>
    a.id.localeCompare(b.id),
  );
  const totalPnl = unique.reduce((sum, p) => sum.plus(p.raw.unrealizedPnl), Big(0));
  const totalCollateral = unique.reduce((sum, p) => sum.plus(p.collateral), Big(0));
  return {
    tradingAvailability,
    abstractionMode: state.abstractionMode,
    spendableUsdcByDex: state.spendableUsdcByDex,
    balanceWithdrawal: getPerpsBalanceWithdrawalPreview(state),
    positions: unique,
    timestamp: Date.now(),
    unavailableDexs: [...new Set(unavailableDexs)],
    totalEquity: unique.reduce((sum, p) => sum.plus(p.equity), Big(0)).toFixed(),
    totalPnl: totalPnl.toFixed(),
    totalReturnOnEquity: totalCollateral.gt(0) ? totalPnl.div(totalCollateral).toFixed() : undefined,
  };
}

/** Reads the account's positions and publishes `updatePerpsPositions` when anything but their read time changed. */
export async function perpsRefreshPositions(accountId: string): Promise<ApiPerpsAccountSnapshot> {
  const sequence = ++readSequence;
  const snapshot = await getPerpsAccountSnapshot(
    accountId, async () => buildPerpsMarketCatalogue(await perpsGetAssets()).assets,
  );
  const newest = newestReads.get(accountId);
  if (newest && newest.sequence > sequence) return newest.snapshot;
  newestReads.set(accountId, { sequence, snapshot });
  const { timestamp, ...content } = snapshot;
  if (!areDeepEqual(content, lastPublished.get(accountId))) {
    lastPublished.set(accountId, content);
    onUpdate?.({ type: 'updatePerpsPositions', accountId, ...snapshot });
  }
  return snapshot;
}

/** Only the iOS app renders positions, so other clients do not poll the backend for them. */
function canPublishPositions() {
  // The environment is set by `initApi`; reads made before it never publish.
  return getEnvironment()?.isIosApp === true;
}

/** Polls the active account's positions. The first read after activation is always published. */
export function setupPerpsPositionsPolling(accountId: string, account: ApiAccountAny) {
  if (!canPublishPositions() || parseAccountId(accountId).network !== 'mainnet'
    || !doesAccountHaveChain(account, 'arbitrum')) return undefined;

  lastPublished.delete(accountId);
  let lastReadAt = Date.now();
  const polling = pollingLoop({
    period: POSITIONS_INTERVAL,
    minDelay: POSITIONS_MIN_DELAY,
    async poll() {
      try {
        await perpsRefreshPositions(accountId);
        lastReadAt = Date.now();
      } catch (err) {
        logDebugError('perpsPositionsPolling', err);
        // With nothing published, the next successful read publishes whether or not anything changed.
        if (Date.now() - lastReadAt >= POSITIONS_UNAVAILABLE_AFTER && lastPublished.delete(accountId)) {
          onUpdate?.({ type: 'updatePerpsPositionsUnavailable', accountId });
        }
      }
    },
  });
  const entry = { accountId, poll: polling.poll };
  activePolling = entry;

  return {
    stop() {
      polling.stop();
      if (activePolling === entry) activePolling = undefined;
    },
  };
}

/** Reads the account right away after an operation changed it: through its polling when active, otherwise once. */
export function requestPerpsPositionsRefresh(accountId: string) {
  if (!canPublishPositions()) return;
  if (activePolling?.accountId === accountId) {
    activePolling.poll();
  } else {
    perpsRefreshPositions(accountId).catch((err) => logDebugError('requestPerpsPositionsRefresh', err));
  }
}
