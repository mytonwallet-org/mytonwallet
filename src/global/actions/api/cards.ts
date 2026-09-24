import type { ApiSubmitTransferOptions } from '../../../api/types';
import type { AccountSettings, GlobalState } from '../../types';
import { MintCardState } from '../../types';

import { DEFAULT_CHAIN, MINT_CARD_ADDRESS, MINT_CARD_COMMENT } from '../../../config';
import { fromDecimal } from '../../../util/decimals';
import { debounce } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import { handleTransferResult, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateAccountSettings, updateAccountState, updateMintCards } from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectMycoin } from '../../selectors';

const CHECK_OWNERSHIP_DEBOUNCE_MS = 3000;

addActionHandler('submitMintCard', withEnclaveSessionRelease(async (global, actions, payload) => {
  const { enclaveToken } = payload ?? {};
  const accountId = selectCurrentAccountId(global)!;

  if (!prepareTransfer(MintCardState.ConfirmHardware, updateMintCards)) {
    return;
  }

  const options = createTransferOptions(getGlobal(), enclaveToken);
  const result = await callApi('submitTransfer', 'ton', options);

  if (!handleTransferResult(result, updateMintCards)) {
    return;
  }

  global = getGlobal();
  global = updateMintCards(global, { state: MintCardState.Done });
  global = updateAccountState(global, accountId, { isCardMinting: true });
  setGlobal(global);
}));

// Called when a card's mint countdown hits zero. Polls the account config once per start time, even if several
// card slides call it at once, and polls again after the modal is reopened
addActionHandler('checkMintStart', (global, actions, { startsAt }) => {
  // With the modal closed, saving `checkedMintStartsAt` would recreate `currentMintCard`, and the next opening
  // would find the start time already checked
  if (!global.currentMintCard || global.currentMintCard.checkedMintStartsAt === startsAt) return undefined;

  // The fresh config arrives as a regular `updateAccountConfig` update
  void callApi('pollAccountConfig');

  return updateMintCards(global, { checkedMintStartsAt: startsAt });
});

function createTransferOptions(globalState: GlobalState, enclaveToken?: string): ApiSubmitTransferOptions {
  const { currentAccountId, currentMintCard } = globalState;
  const { config } = selectAccountState(globalState, currentAccountId!)!;
  const mycoin = selectMycoin(globalState);
  const { cardsInfo } = config!;
  const type = currentMintCard!.type!;
  const cardInfo = cardsInfo![type];

  return {
    accountId: currentAccountId!,
    enclaveToken,
    toAddress: MINT_CARD_ADDRESS,
    amount: fromDecimal(cardInfo.price, mycoin.decimals),
    tokenAddress: mycoin.tokenAddress,
    payload: { type: 'comment', text: MINT_CARD_COMMENT },
  };
}

// Debounced to avoid API rate limits: NFT update events fire per-account, causing a burst of ownership checks
const accountIdsToCheckCardNftOwnership = new Set<string>();

const checkCardNftOwnershipDebounced = debounce(() => {
  const byAccountId = getGlobal().settings.byAccountId;

  accountIdsToCheckCardNftOwnership.forEach((accountId) => {
    const settings = byAccountId[accountId];
    if (settings) {
      void checkOwnershipForAccount(accountId, settings);
    }
  });

  accountIdsToCheckCardNftOwnership.clear();
}, CHECK_OWNERSHIP_DEBOUNCE_MS, false, true);

addActionHandler('checkCardNftOwnership', (global, actions, payload) => {
  const { accountId } = payload || {};

  if (accountId) {
    accountIdsToCheckCardNftOwnership.add(accountId);
  } else {
    Object.keys(global.settings.byAccountId).forEach((id) => accountIdsToCheckCardNftOwnership.add(id));
  }

  checkCardNftOwnershipDebounced();
});

async function checkOwnershipForAccount(accountId: string, settings: AccountSettings) {
  const cardBackgroundNftAddress = settings.cardBackgroundNft?.address;
  const accentColorNftAddress = settings.accentColorNft?.address;

  if (!cardBackgroundNftAddress && !accentColorNftAddress) return;

  const chain = settings.accentColorNft?.chain || DEFAULT_CHAIN;

  const [isCardBackgroundNftOwned, isAccentColorNftOwned] = await Promise.all([
    cardBackgroundNftAddress
      ? callApi('checkNftOwnership', chain, accountId, cardBackgroundNftAddress)
      : undefined,
    accentColorNftAddress && accentColorNftAddress !== cardBackgroundNftAddress
      ? callApi('checkNftOwnership', chain, accountId, accentColorNftAddress)
      : undefined,
  ]);

  let newGlobal = getGlobal();
  const newAccountSettings = newGlobal.settings.byAccountId[accountId];

  if (cardBackgroundNftAddress && isCardBackgroundNftOwned === false
    && newAccountSettings?.cardBackgroundNft?.address === cardBackgroundNftAddress) {
    newGlobal = updateAccountSettings(newGlobal, accountId, {
      cardBackgroundNft: undefined,
    });
  }

  if (accentColorNftAddress
    && newAccountSettings?.accentColorNft?.address === accentColorNftAddress
    && (
      (accentColorNftAddress === cardBackgroundNftAddress && isCardBackgroundNftOwned === false)
      || (accentColorNftAddress !== cardBackgroundNftAddress && isAccentColorNftOwned === false)
    )) {
    newGlobal = updateAccountSettings(newGlobal, accountId, {
      accentColorNft: undefined,
      accentColorIndex: undefined,
    });
  }

  setGlobal(newGlobal);
}
