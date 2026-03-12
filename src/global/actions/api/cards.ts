import type { ApiSubmitTransferOptions } from '../../../api/types';
import type { AccountSettings, GlobalState } from '../../types';
import { MintCardState } from '../../types';

import { DEFAULT_CHAIN, IS_CORE_WALLET, MINT_CARD_ADDRESS, MINT_CARD_COMMENT } from '../../../config';
import { fromDecimal } from '../../../util/decimals';
import { debounce } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { handleTransferResult, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateAccountSettings, updateAccountState, updateMintCards } from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectMycoin } from '../../selectors';

const CHECK_OWNERSHIP_DEBOUNCE_MS = 3000;

addActionHandler('submitMintCard', async (global, actions, { password } = {}) => {
  const accountId = selectCurrentAccountId(global)!;

  if (!await prepareTransfer(MintCardState.ConfirmHardware, updateMintCards, password)) {
    return;
  }

  const options = createTransferOptions(getGlobal(), password);
  const result = await callApi('submitTransfer', 'ton', options);

  if (!handleTransferResult(result, updateMintCards)) {
    return;
  }

  global = getGlobal();
  global = updateMintCards(global, { state: MintCardState.Done });
  global = updateAccountState(global, accountId, { isCardMinting: true });
  setGlobal(global);
});

function createTransferOptions(globalState: GlobalState, password?: string): ApiSubmitTransferOptions {
  const { currentAccountId, currentMintCard } = globalState;
  const { config } = selectAccountState(globalState, currentAccountId!)!;
  const mycoin = selectMycoin(globalState);
  const { cardsInfo } = config!;
  const type = currentMintCard!.type!;
  const cardInfo = cardsInfo![type];

  return {
    accountId: currentAccountId!,
    password,
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
  if (IS_CORE_WALLET) return;

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
