import './initial';

import type { ApiBaseCurrency, ApiNft } from '../../../api/types';
import type { ApiUpdate } from '../../../api/types/updates';
import type { GlobalState } from '../../types';

import { addActionHandler, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

type ApiUpdateHandler = (
  global: GlobalState,
  actions: AnyLiteral,
  update: ApiUpdate,
) => void;

function getApiUpdateHandler() {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([name]) => name === 'apiUpdate');
  return call![1] as ApiUpdateHandler;
}

function makeGlobal(currentAccountId: string): GlobalState {
  const account = { title: 'Test', type: 'mnemonic', byChain: {} };
  const accountIds = ['0-ton-mainnet', '0-ton-testnet'];
  return {
    currentAccountId,
    accounts: { byId: Object.fromEntries(accountIds.map((id) => [id, account])) },
    byAccountId: Object.fromEntries(accountIds.map((id) => [id, {}])),
    settings: {
      byAccountId: Object.fromEntries(accountIds.map((id) => [id, {}])),
      orderedAccountIds: accountIds,
    },
    pushNotifications: { enabledAccounts: [] },
  } as unknown as GlobalState;
}

describe('updateNfts api update', () => {
  const ACCOUNT_ID = '0-ton-mainnet';
  const NFT_ADDRESS = 'EQAglL_g6q2AhMK_BT9jN1F-8jBlv2pOI30vRkPluU9kcXgV';

  function makeNft(partial: Partial<ApiNft> = {}): ApiNft {
    return {
      chain: 'ton',
      interface: 'default',
      index: 0,
      address: NFT_ADDRESS,
      isOnSale: false,
      metadata: {},
      ...partial,
    };
  }

  function dispatchUpdateNfts(global: GlobalState, nfts: ApiNft[], isFullLoading?: boolean) {
    getApiUpdateHandler()(global, { checkCardNftOwnership: jest.fn() }, {
      type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts, isFullLoading,
    });
    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    return (updatedGlobal as GlobalState).byAccountId[ACCOUNT_ID].nfts!.byAddress![NFT_ADDRESS];
  }

  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
  });

  it('drops a stale unverified flag when the collection has become trusted', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.byAccountId[ACCOUNT_ID].nfts = {
      byAddress: { [NFT_ADDRESS]: makeNft({ isUnverified: true }) },
      orderedAddresses: [NFT_ADDRESS],
    };

    expect(dispatchUpdateNfts(global, [makeNft()], true).isUnverified).toBeUndefined();
  });

  it('keeps the unverified flag while the incoming batch still reports it', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.byAccountId[ACCOUNT_ID].nfts = {
      byAddress: { [NFT_ADDRESS]: makeNft({ isUnverified: true }) },
      orderedAddresses: [NFT_ADDRESS],
    };

    expect(dispatchUpdateNfts(global, [makeNft({ isUnverified: true })], true).isUnverified).toBe(true);
  });

  it('keeps the stored NFT data that the batch has no fresher version of', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.byAccountId[ACCOUNT_ID].nfts = {
      byAddress: { [NFT_ADDRESS]: makeNft({ isOnSale: true, name: 'From socket' }) },
      orderedAddresses: [NFT_ADDRESS],
    };

    const nft = dispatchUpdateNfts(global, [makeNft({ isOnSale: false, name: 'From batch' })], true);

    expect(nft).toMatchObject({ isOnSale: true, name: 'From socket' });
  });
});

describe('removeAccounts api update', () => {
  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
  });

  function dispatchRemoveAccounts(global: GlobalState, accountIds: string[]) {
    const actions = { switchAccount: jest.fn() };
    getApiUpdateHandler()(global, actions, { type: 'removeAccounts', accountIds });
    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    return { actions, updatedGlobal: updatedGlobal as GlobalState };
  }

  it('re-selects a surviving account when the removed one was current', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(makeGlobal('0-ton-testnet'), ['0-ton-testnet']);

    expect(updatedGlobal.byAccountId).not.toHaveProperty('0-ton-testnet');
    expect(actions.switchAccount).toHaveBeenCalledWith({ accountId: '0-ton-mainnet', newNetwork: 'mainnet' });
  });

  it('skips a stale ordered id that no longer has an account when picking the survivor', () => {
    const global = makeGlobal('0-ton-testnet');
    // `orderedAccountIds` retains a ghost id from an account removed in an earlier session (never cleaned there).
    global.settings.orderedAccountIds = ['9-ton-mainnet', '0-ton-mainnet', '0-ton-testnet'];

    const { actions } = dispatchRemoveAccounts(global, ['0-ton-testnet']);

    expect(actions.switchAccount).toHaveBeenCalledWith({ accountId: '0-ton-mainnet', newNetwork: 'mainnet' });
  });

  it('does not switch when the current account survives', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(makeGlobal('0-ton-mainnet'), ['0-ton-testnet']);

    expect(updatedGlobal.currentAccountId).toBe('0-ton-mainnet');
    expect(actions.switchAccount).not.toHaveBeenCalled();
  });

  it('leaves no account selected after a full wipe', () => {
    const { actions, updatedGlobal } = dispatchRemoveAccounts(
      makeGlobal('0-ton-testnet'),
      ['0-ton-mainnet', '0-ton-testnet'],
    );

    expect(updatedGlobal.currentAccountId).toBeUndefined();
    expect(actions.switchAccount).not.toHaveBeenCalled();
  });
});

describe('updateConfig api update', () => {
  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
  });

  function makeGlobalWithRestrictions(allowedOnOffRampCurrencies?: ApiBaseCurrency[]): GlobalState {
    return {
      restrictions: { allowedOnOffRampCurrencies },
      settings: { byAccountId: {} },
    } as unknown as GlobalState;
  }

  function dispatchUpdateConfig(global: GlobalState, allowed?: string[]) {
    getApiUpdateHandler()(global, {}, {
      type: 'updateConfig',
      isLimited: false,
      isCopyStorageEnabled: false,
      isAppUpdateRequired: false,
      seasonalTheme: undefined,
      allowedOnOffRampCurrencies: allowed,
    } as ApiUpdate);
    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    return updatedGlobal as GlobalState;
  }

  it('normalizes the allowed ramp currencies into upper-case known codes', () => {
    const updatedGlobal = dispatchUpdateConfig(makeGlobalWithRestrictions(undefined), ['usd', 'rub', 'xyz']);

    expect(updatedGlobal.restrictions.allowedOnOffRampCurrencies).toEqual(['USD', 'RUB']);
  });

  it('keeps the previous array reference when the list is unchanged', () => {
    const previous: ApiBaseCurrency[] = ['USD', 'RUB'];
    const updatedGlobal = dispatchUpdateConfig(makeGlobalWithRestrictions(previous), ['usd', 'rub']);

    expect(updatedGlobal.restrictions.allowedOnOffRampCurrencies).toBe(previous);
  });

  it('clears the field when the backend omits it', () => {
    const updatedGlobal = dispatchUpdateConfig(makeGlobalWithRestrictions(['USD']), undefined);

    expect(updatedGlobal.restrictions.allowedOnOffRampCurrencies).toBeUndefined();
  });

  it('treats a malformed payload as an absent field', () => {
    const updatedGlobal = dispatchUpdateConfig(makeGlobalWithRestrictions(['USD']), 'rub' as unknown as string[]);

    expect(updatedGlobal.restrictions.allowedOnOffRampCurrencies).toBeUndefined();
  });
});
