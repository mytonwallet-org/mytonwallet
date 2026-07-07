import type { ApiActivity, ApiChain, ApiTransactionActivity } from '../../../api/types';
import type { GlobalState } from '../../types';

import {
  IS_CORE_WALLET,
  MINT_CARD_ADDRESS,
  MINT_CARD_REFUND_COMMENT,
  MW_CARDS_COLLECTION,
} from '../../../config';
import { getActivityIdReplacements, getIsHiddenNftActivity } from '../../../util/activities';
import { playIncomingTransactionSound } from '../../../util/notificationSound';
import { getIsTransactionWithPoisoning, updatePoisoningCacheFromActivities } from '../../../util/poisoningHash';
import { waitFor } from '../../../util/schedulers';
import { getChainBySlug } from '../../../util/tokens';
import { SEC } from '../../../api/constants';
import { getIsTinyOrScamTransaction } from '../../helpers';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import {
  addInitialActivities,
  addNewActivities,
  addNft,
  applyIncomingNftFromActivity,
  applyOutgoingNftFromActivity,
  removeActivities,
  replaceCurrentActivityId,
  replaceCurrentDomainLinkingId,
  replaceCurrentDomainRenewalId,
  replaceCurrentSwapId,
  replaceCurrentTransferId,
  updateAccountState,
  updatePendingActivitiesToTrustedByReplacements,
  updatePendingActivitiesWithTrustedStatus,
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

addActionHandler('apiUpdate', (global, actions, update) => {
  switch (update.type) {
    case 'initialActivities': {
      const {
        accountId, mainActivities, mainHistoryHasMore, bySlug, chain,
      } = update;

      updatePoisoningCacheFromActivities(mainActivities);

      global = addInitialActivities(global, accountId, mainActivities, bySlug, chain, mainHistoryHasMore);
      setGlobal(global);

      void preloadTopTokenHistory(accountId, chain);
      break;
    }

    case 'newLocalActivities': {
      const {
        accountId,
        activities,
      } = update;

      // Find matches between local and chain activities
      const replacedIds = findLocalToChainActivityMatches(global, accountId, activities);

      hideOutdatedLocalActivities(activities, replacedIds);

      // Update pending chain activities to trusted status where applicable
      global = updatePendingActivitiesToTrustedByReplacements(global, accountId, activities, replacedIds);
      global = addNewActivities(global, accountId, activities);

      setGlobal(global);
      break;
    }

    case 'newActivities': {
      const { accountId, activities: newConfirmedActivities, pendingActivities, chain } = update;

      const prevActivitiesForReplacement = [
        ...selectLocalActivitiesSlow(global, accountId),
        ...(chain ? selectPendingActivitiesSlow(global, accountId, chain) : []),
      ];
      const incomingActivities = [
        ...(pendingActivities ?? []),
        ...newConfirmedActivities,
      ];
      const replacedIds = getActivityIdReplacements(prevActivitiesForReplacement, incomingActivities);

      // A good TON address for testing: UQD5mxRgCuRNLxKxeOjG6r14iSroLF5FtomPnet-sgP5xI-e
      global = removeActivities(global, accountId, Object.keys(replacedIds));
      global = updatePendingActivitiesWithTrustedStatus(
        global,
        accountId,
        chain,
        pendingActivities,
        replacedIds,
        prevActivitiesForReplacement,
      );
      global = addNewActivities(global, accountId, newConfirmedActivities);

      global = replaceCurrentTransferId(global, replacedIds);
      global = replaceCurrentDomainLinkingId(global, replacedIds);
      global = replaceCurrentDomainRenewalId(global, replacedIds);
      global = replaceCurrentSwapId(global, replacedIds);
      global = replaceCurrentActivityId(global, accountId, replacedIds);

      notifyAboutNewActivities(global, accountId, newConfirmedActivities);
      updatePoisoningCacheFromActivities(newConfirmedActivities);

      if (!IS_CORE_WALLET) {
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

            if (activity.nft.collectionAddress === MW_CARDS_COLLECTION) {
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

        // Left intact: handles the `isCardMinting` flag reset and refund branch. `addNft`/`setCardBackgroundNft`
        // are idempotent, so the small overlap with the loop above is harmless.
        global = processCardMintingActivity(global, accountId, newConfirmedActivities);
      }

      setGlobal(global);
      break;
    }
  }
});

function notifyAboutNewActivities(global: GlobalState, accountId: string, newActivities: ApiActivity[]) {
  if (!global.settings.canPlaySounds) {
    return;
  }

  const { areTinyTransfersHidden } = global.settings;
  const { blacklistedNftAddresses, whitelistedNftAddresses } = selectAccountState(global, accountId) || {};

  const shouldPlaySound = newActivities.some((activity) => {
    return activity.kind === 'transaction'
      && activity.isIncoming
      && activity.status === 'completed'
      && (Date.now() - activity.timestamp < TX_AGE_TO_PLAY_SOUND)
      && !(
        areTinyTransfersHidden
        && (
          getIsTinyOrScamTransaction(activity, global.tokenInfo?.bySlug[activity.slug])
          || getIsHiddenNftActivity(activity, blacklistedNftAddresses, whitelistedNftAddresses)
        )
      )
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

function findLocalToChainActivityMatches(
  global: GlobalState,
  accountId: string,
  localActivities: ApiActivity[],
) {
  const maxCheckDepth = localActivities.length + 20;
  const chainActivities = selectRecentNonLocalActivitiesSlow(global, accountId, maxCheckDepth);

  return getActivityIdReplacements(localActivities, chainActivities);
}

/**
 * Thanks to the socket, there is a possibility that a pending activity will arrive before the corresponding local
 * activity. Such local activities duplicate the pending activities, which is unwanted. They shouldn't be removed,
 * because other parts of the global state may point to their ids, so they get hidden instead.
 */
function hideOutdatedLocalActivities(
  localActivities: ApiActivity[],
  replacements: Record<string, string>,
) {
  for (const localActivity of localActivities) {
    if (localActivity.id in replacements) {
      localActivity.shouldHide = true;
    }
  }
}

async function preloadTopTokenHistory(accountId: string, chain: ApiChain) {
  await waitFor(() => !!selectAccountTokens(getGlobal(), accountId), SEC, 10);
  const global = getGlobal();

  const tokens = (selectAccountTokens(global, accountId) ?? [])
    .slice(0, PRELOAD_ACTIVITY_TOKEN_COUNT)
    .filter((token) => getChainBySlug(token.slug) === chain);

  const { idsBySlug } = selectAccountState(global, accountId)?.activities || {};
  const { fetchPastActivities } = getActions();

  for (const { slug } of tokens) {
    if (idsBySlug?.[slug] === undefined) {
      fetchPastActivities({ accountId, slug });
    }
  }
}
