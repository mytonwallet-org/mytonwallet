import type { ApiActivity, ApiChain, ApiTransactionActivity } from '../../../api/types';
import type { GlobalState } from '../../types';

import {
  IS_CORE_WALLET,
  MINT_CARD_ADDRESS,
  MINT_CARD_REFUND_COMMENT,
  MTW_CARDS_COLLECTION,
} from '../../../config';
import { getActivityIdReplacements } from '../../../util/activities';
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
      const { accountId, mainActivities, bySlug, chain } = update;

      updatePoisoningCacheFromActivities(mainActivities);

      global = addInitialActivities(global, accountId, mainActivities, bySlug, chain);
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

      notifyAboutNewActivities(global, newConfirmedActivities);
      updatePoisoningCacheFromActivities(newConfirmedActivities);

      if (!IS_CORE_WALLET) {
        // NFT polling is executed at long intervals, so it is more likely that a user will see a new transaction
        // rather than receiving a card in the collection. Therefore, when a new activity occurs,
        // we check for a card from the MyTonWallet collection and apply it.
        global = processCardMintingActivity(global, accountId, newConfirmedActivities);
      }

      setGlobal(global);
      break;
    }
  }
});

function notifyAboutNewActivities(global: GlobalState, newActivities: ApiActivity[]) {
  if (!global.settings.canPlaySounds) {
    return;
  }

  const shouldPlaySound = newActivities.some((activity) => {
    return activity.kind === 'transaction'
      && activity.isIncoming
      && activity.status === 'completed'
      && (Date.now() - activity.timestamp < TX_AGE_TO_PLAY_SOUND)
      && !(
        global.settings.areTinyTransfersHidden
        && getIsTinyOrScamTransaction(activity, global.tokenInfo?.bySlug[activity.slug])
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
      && activity?.nft?.collectionAddress === MTW_CARDS_COLLECTION;
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
    getActions().setCardBackgroundNft({ nft });
    getActions().installAccentColorFromNft({ nft });
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
      fetchPastActivities({ slug });
    }
  }
}
