import type { ApiSubmitTransferOptions } from '../../../api/types';
import type { GlobalState } from '../../types';
import { MintCardState } from '../../types';

import { DEFAULT_CHAIN, IS_CORE_WALLET, MINT_CARD_ADDRESS, MINT_CARD_COMMENT } from '../../../config';
import { fromDecimal } from '../../../util/decimals';
import { callApi } from '../../../api';
import { handleTransferResult, prepareTransfer } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { updateAccountSettings, updateAccountState, updateMintCards } from '../../reducers';
import { selectAccountState, selectCurrentAccountId, selectMycoin } from '../../selectors';

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

addActionHandler('checkCardNftOwnership', (global) => {
  if (IS_CORE_WALLET) return;

  const { byAccountId } = global.settings;

  Object.entries(byAccountId).forEach(async ([accountId, settings]) => {
    const cardBackgroundNftAddress = settings.cardBackgroundNft?.address;
    const accentColorNftAddress = settings.accentColorNft?.address;

    if (!cardBackgroundNftAddress && !accentColorNftAddress) return;

    const chain = settings.accentColorNft?.chain || DEFAULT_CHAIN;

    const promises = [
      cardBackgroundNftAddress
        ? callApi('checkNftOwnership', chain, accountId, cardBackgroundNftAddress)
        : undefined,
      accentColorNftAddress && accentColorNftAddress !== cardBackgroundNftAddress
        ? callApi('checkNftOwnership', chain, accountId, accentColorNftAddress)
        : undefined,
    ];

    const [isCardBackgroundNftOwned, isAccentColorNftOwned] = await Promise.all(promises);

    let newGlobal = getGlobal();

    if (cardBackgroundNftAddress && isCardBackgroundNftOwned === false) {
      newGlobal = updateAccountSettings(newGlobal, accountId, {
        cardBackgroundNft: undefined,
      });
    }

    if (accentColorNftAddress && (
      (accentColorNftAddress === cardBackgroundNftAddress && isCardBackgroundNftOwned === false)
      || (accentColorNftAddress !== cardBackgroundNftAddress && isAccentColorNftOwned === false)
    )) {
      newGlobal = updateAccountSettings(newGlobal, accountId, {
        accentColorNft: undefined,
        accentColorIndex: undefined,
      });
    }

    setGlobal(newGlobal);
  });
});
