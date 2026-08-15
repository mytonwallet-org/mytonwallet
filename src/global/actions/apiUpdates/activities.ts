import type { ApiActivity, ApiChain, ApiTransactionActivity } from '../../../api/types';
import type { GlobalState } from '../../types';

import {
  IS_FEATURE_LIMITED,
  IS_MY_WALLET_BRAND,
  MINT_CARD_ADDRESS,
  MINT_CARD_REFUND_COMMENT,
  MW_CARDS_COLLECTION,
} from '../../../config';
import { getIsHiddenNftActivity } from '../../../util/activities';
import { playIncomingTransactionSound } from '../../../util/notificationSound';
import { getIsTransactionWithPoisoning, updatePoisoningCacheFromActivities } from '../../../util/poisoningHash';
import { waitFor } from '../../../util/schedulers';
import { getChainBySlug } from '../../../util/tokens';
import { callApi } from '../../../api';
import { SEC } from '../../../api/constants';
import { getIsTinyOrScamTransaction } from '../../helpers';
import { runActivityUpdateInOrder } from '../../helpers/activityUpdateQueue';
import {
  selectCexSwapRefreshContextActivities,
} from '../../helpers/cexSwapRefresh';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import {
  addInitialActivities,
  addNewActivities,
  addNft,
  applyActivitiesPatch,
  applyIncomingNftFromActivity,
  applyOutgoingNftFromActivity,
  replaceCurrentActivityId,
  replaceCurrentDomainLinkingId,
  replaceCurrentDomainRenewalId,
  replaceCurrentSwapId,
  replaceCurrentTransferId,
  replacePendingActivities,
  updateAccountState,
  whitelistNft,
} from '../../reducers';
import {
  selectAccountSettings,
  selectAccountState,
  selectAccountTokens,
  selectLocalActivitiesSlow,
  selectPendingActivitiesSlow,
  selectRecentNonLocalActivitiesSlow,
} from '../../selectors';

const TX_AGE_TO_PLAY_SOUND = 60000; // 1 min
const PRELOAD_ACTIVITY_TOKEN_COUNT = 10;

addActionHandler('apiUpdate', async (global, actions, update) => {
  switch (update.type) {
    case 'initialActivities': {
      const {
        accountId, mainActivities, mainHistoryHasMore, bySlug, chain,
      } = update;

      updatePoisoningCacheFromActivities(mainActivities);

      const currentActivities = Object.values(selectAccountState(global, accountId)?.activities?.byId ?? {});
      const duplicateIds = await callApi(
        'getBackendDexSwapIdsDuplicatedByTonAggregates',
        accountId,
        [...currentActivities, ...mainActivities],
      );
      global = getGlobal();
      global = addInitialActivities(global, accountId, mainActivities, bySlug, chain, mainHistoryHasMore);
      if (duplicateIds?.length) {
        global = applyActivitiesPatch(global, accountId, { upsert: [], removeIds: duplicateIds });
      }
      setGlobal(global);

      void preloadTopTokenHistory(accountId, chain);
      break;
    }

    case 'newLocalActivities': {
      const {
        accountId,
        activities,
      } = update;

      await runActivityUpdateInOrder(accountId, async () => {
        global = getGlobal();

        const maxCheckDepth = activities.length + 20;
        const chainActivities = selectRecentNonLocalActivitiesSlow(global, accountId, maxCheckDepth);
        const reconciliation = await callApi(
          'reconcileActivityUpdate',
          accountId,
          activities,
          chainActivities,
          undefined,
        );
        global = getGlobal();

        let localActivities = activities;
        if (reconciliation) {
          const { patch } = reconciliation;
          const replacedIds = patch.replacedIds ?? {};
          const removeIds = new Set(patch.removeIds);
          const localIds = new Set(activities.map(({ id }) => id));
          const patchUpsertById = new Map(patch.upsert.map((activity) => [activity.id, activity]));

          localActivities = activities
            .filter(({ id }) => !removeIds.has(id))
            .map((activity) => patchUpsertById.get(activity.id) ?? activity);

          global = addNewActivities(
            global,
            accountId,
            patch.upsert.filter(({ id }) => !localIds.has(id)),
          );
          global = replaceCurrentTransferId(global, replacedIds);
          global = replaceCurrentDomainLinkingId(global, replacedIds);
          global = replaceCurrentDomainRenewalId(global, replacedIds);
          global = replaceCurrentSwapId(global, replacedIds);
          global = replaceCurrentActivityId(global, accountId, replacedIds);
        }

        // If the SDK bridge is unavailable, keep local and chain rows separate. Native/app code must not infer identity.
        global = addNewActivities(global, accountId, localActivities);
        if (reconciliation) {
          global = applyActivitiesPatch(global, accountId, reconciliation.patch);
        }

        setGlobal(global);
      });
      break;
    }

    case 'newActivities': {
      const { accountId, activities: newConfirmedActivities, pendingActivities, chain } = update;
      await runActivityUpdateInOrder(accountId, async () => {
        global = getGlobal();
        const { activities } = selectAccountState(global, accountId) ?? {};
        const prevActivitiesForReplacement = [
          ...selectLocalActivitiesSlow(global, accountId),
          ...(chain ? selectPendingActivitiesSlow(global, accountId, chain) : []),
        ];
        const reconciliation = await callApi(
          'reconcileActivityUpdate',
          accountId,
          prevActivitiesForReplacement,
          newConfirmedActivities,
          pendingActivities,
          {
            contextActivities: activities
              ? selectCexSwapRefreshContextActivities(activities, [], newConfirmedActivities)
              : newConfirmedActivities,
          },
        );
        global = getGlobal();
        const replacedIds = reconciliation?.patch.replacedIds ?? {};
        const reconciledConfirmedActivities = reconciliation?.confirmedActivities ?? newConfirmedActivities;
        const reconciledPendingActivities = reconciliation?.pendingActivities ?? pendingActivities;

        if (chain && reconciledPendingActivities) {
          global = replacePendingActivities(global, accountId, chain, reconciledPendingActivities);
        }
        // Fail closed on bridge errors: commit raw rows, but never infer replacements or visibility in app code.
        global = addNewActivities(global, accountId, reconciledConfirmedActivities);
        if (reconciliation) {
          global = applyActivitiesPatch(global, accountId, reconciliation.patch);
        }
        global = replaceCurrentTransferId(global, replacedIds);
        global = replaceCurrentDomainLinkingId(global, replacedIds);
        global = replaceCurrentDomainRenewalId(global, replacedIds);
        global = replaceCurrentSwapId(global, replacedIds);
        global = replaceCurrentActivityId(global, accountId, replacedIds);

        notifyAboutNewActivities(
          global,
          accountId,
          reconciledConfirmedActivities.filter(({ shouldHide }) => shouldHide !== true),
        );
        updatePoisoningCacheFromActivities(newConfirmedActivities);

        if (!IS_FEATURE_LIMITED) {
          // NFT polling is executed at long intervals, so a transaction-event with an NFT can arrive
          // long before the next polling round. Apply the change to local NFT state immediately so the UI
          // reflects new ownership (incl. MW-card auto-install) without waiting for polling.
          // A subsequent `nftReceived`/`nftSent` socket update or polling round is idempotent here.
          for (const activity of newConfirmedActivities) {
            if (activity.kind !== 'transaction' || !activity.nft) continue;

            // For `nftTrade` (marketplace buy/sell) `isIncoming` reflects the `TONCOIN` direction,
            // not the NFT direction - so it must be inverted here
            const isNftIncoming = activity.type === 'nftTrade' ? !activity.isIncoming : activity.isIncoming;

            if (isNftIncoming) {
              global = applyIncomingNftFromActivity(global, accountId, activity.nft);

              if (activity.type === 'nftTrade') {
                global = whitelistNft(global, accountId, activity.nft.address);
              }

              // Auto-installing a card is only safe where the card can also be taken off: every removal surface
              // (customization modal, accent picker, the NFT menu's reset action) belongs to the My Wallet brand
              if (IS_MY_WALLET_BRAND && activity.nft.collectionAddress === MW_CARDS_COLLECTION) {
                const settings = selectAccountSettings(global, accountId);

                if (!settings?.cardBackgroundNft) {
                  getActions().setCardBackgroundNft({ nft: activity.nft, accountId });
                  getActions().installAccentColorFromNft({ nft: activity.nft, accountId });
                }
              }
            } else {
              // `newOwnerAddress` is `unknown` from the sender's activity; `ownedSet` pruning is the meaningful effect
              global = applyOutgoingNftFromActivity(global, accountId, activity.nft);
            }
          }

          // Handles the `isCardMinting` flag reset and refund branch. `addNft`/`setCardBackgroundNft` are
          // idempotent, so the small overlap with the loop above is harmless.
          if (IS_MY_WALLET_BRAND) {
            global = processCardMintingActivity(global, accountId, newConfirmedActivities);
          }
        }

        setGlobal(global);
      });

      break;
    }
  }
});

function notifyAboutNewActivities(global: GlobalState, accountId: string, newActivities: ApiActivity[]) {
  if (!global.settings.canPlaySounds) {
    return;
  }

  const { areTinyTransfersHidden, areUnverifiedNftsHidden } = global.settings;
  const { blacklistedNftAddresses, whitelistedNftAddresses } = selectAccountState(global, accountId) || {};

  const shouldPlaySound = newActivities.some((activity) => {
    return activity.kind === 'transaction'
      && activity.isIncoming
      && activity.status === 'completed'
      && (Date.now() - activity.timestamp < TX_AGE_TO_PLAY_SOUND)
      && !getIsHiddenNftActivity(activity, blacklistedNftAddresses, whitelistedNftAddresses, areUnverifiedNftsHidden)
      && !(areTinyTransfersHidden && getIsTinyOrScamTransaction(activity, global.tokenInfo?.bySlug[activity.slug]))
      && !getIsTransactionWithPoisoning(activity);
  });

  if (shouldPlaySound) {
    playIncomingTransactionSound();
  }
}

function processCardMintingActivity(global: GlobalState, accountId: string, activities: ApiActivity[]): GlobalState {
  const { isCardMinting } = selectAccountState(global, accountId) || {};

  if (!isCardMinting || !activities.length) {
    return global;
  }

  const mintCardActivity = activities.find((activity) => {
    return activity.kind === 'transaction'
      && activity.isIncoming
      && activity?.nft?.collectionAddress === MW_CARDS_COLLECTION;
  });

  const refundActivity = activities.find((activity) => {
    return activity.kind === 'transaction'
      && activity.isIncoming
      && activity.fromAddress === MINT_CARD_ADDRESS
      && activity?.comment === MINT_CARD_REFUND_COMMENT;
  });

  if (mintCardActivity) {
    const nft = (mintCardActivity as ApiTransactionActivity).nft!;

    global = updateAccountState(global, accountId, { isCardMinting: undefined });
    global = addNft(global, accountId, nft);
    getActions().setCardBackgroundNft({ nft, accountId });
    getActions().installAccentColorFromNft({ nft, accountId });
  } else if (refundActivity) {
    global = updateAccountState(global, accountId, { isCardMinting: undefined });
  }

  return global;
}

async function preloadTopTokenHistory(accountId: string, chain: ApiChain) {
  const { fetchPastActivities } = getActions();

  await waitFor(() => !!selectAccountTokens(getGlobal(), accountId), SEC, 10);
  const global = getGlobal();

  const tokens = (selectAccountTokens(global, accountId) ?? [])
    .slice(0, PRELOAD_ACTIVITY_TOKEN_COUNT)
    .filter((token) => getChainBySlug(token.slug) === chain);

  const { idsBySlug } = selectAccountState(global, accountId)?.activities || {};

  for (const { slug } of tokens) {
    if (idsBySlug?.[slug] === undefined) {
      fetchPastActivities({ accountId, slug });
    }
  }
}
