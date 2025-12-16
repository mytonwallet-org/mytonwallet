import type { GlobalState } from '../../types';
import { MintCardState } from '../../types';

import { getAccentColorIndexFromNft } from '../../../util/accentColor';
import { callActionInMain } from '../../../util/multitab';
import { IS_DELEGATED_BOTTOM_SHEET } from '../../../util/windowEnvironment';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { resetHardware, updateCurrentAccountSettings, updateMintCards } from '../../reducers';
import { selectIsHardwareAccount } from '../../selectors';

addActionHandler('openMintCardModal', (global): GlobalState => {
  return updateMintCards(global, { state: MintCardState.Initial });
});

addActionHandler('closeMintCardModal', (global): GlobalState => {
  return { ...global, currentMintCard: undefined };
});

addActionHandler('startCardMinting', (global, action, { type }): GlobalState => {
  if (selectIsHardwareAccount(global)) {
    global = resetHardware(global, 'ton');
    global = updateMintCards(global, { state: MintCardState.ConnectHardware });
  } else {
    global = updateMintCards(global, { state: MintCardState.Password });
  }

  return updateMintCards(global, { type });
});

addActionHandler('clearMintCardError', (global): GlobalState => {
  return updateMintCards(global, { error: undefined });
});

addActionHandler('setCardBackgroundNft', (global, actions, { nft }) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('setCardBackgroundNft', { nft });
    return;
  }

  global = updateCurrentAccountSettings(global, { cardBackgroundNft: nft });
  setGlobal(global);
});

addActionHandler('clearCardBackgroundNft', (global) => {
  if (IS_DELEGATED_BOTTOM_SHEET) {
    callActionInMain('clearCardBackgroundNft');
    return;
  }

  global = updateCurrentAccountSettings(global, { cardBackgroundNft: undefined });
  setGlobal(global);
});

addActionHandler('installAccentColorFromNft', async (global, actions, { nft }) => {
  const accentColorIndex = await getAccentColorIndexFromNft(nft);

  global = getGlobal();
  global = updateCurrentAccountSettings(global, {
    accentColorNft: nft,
    accentColorIndex,
  });
  setGlobal(global);
});

addActionHandler('clearAccentColorFromNft', (global) => {
  return updateCurrentAccountSettings(global, {
    accentColorNft: undefined,
    accentColorIndex: undefined,
  });
});
