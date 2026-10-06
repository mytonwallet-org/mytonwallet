import './initial';

import type { ApiBaseCurrency, ApiNft } from '../../../api/types';
import type { ApiUpdate } from '../../../api/types/updates';
import type { GlobalState } from '../../types';
import { AppState } from '../../types';

import { callApi, callApiWithThrow } from '../../../api';
import { persistCache } from '../../cache';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../../api', () => ({ callApi: jest.fn(), callApiWithThrow: jest.fn() }));
jest.mock('../../cache', () => ({ persistCache: jest.fn(() => true) }));

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

describe('updateAccount api update', () => {
  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
  });

  it('applies account-level type changes to global account state', () => {
    const global = makeGlobal('0-ton-mainnet');

    getApiUpdateHandler()(global, {}, {
      type: 'updateAccount',
      accountId: '0-ton-mainnet',
      accountType: 'view',
    });

    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    expect((updatedGlobal as GlobalState).accounts!.byId['0-ton-mainnet'].type).toBe('view');
    expect((updatedGlobal as GlobalState).accounts!.byId['0-ton-testnet'].type).toBe('mnemonic');
  });
});

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
    jest.mocked(callApi).mockClear();
    jest.mocked(callApiWithThrow).mockReset().mockResolvedValue(undefined);
    jest.mocked(persistCache).mockClear();
    jest.mocked(persistCache).mockReturnValue(true);
    jest.mocked(setGlobal).mockImplementation((global) => {
      jest.mocked(getGlobal).mockReturnValue(global);
    });
  });

  it('confirms full NFT coverage only after a successful stream, including an empty stream', () => {
    let global = makeGlobal(ACCOUNT_ID);
    const actions = { checkCardNftOwnership: jest.fn() };
    const updates: Array<Pick<Extract<ApiUpdate, { type: 'updateNfts' }>, 'isFullLoading' | 'streamedAddresses'>> = [
      { isFullLoading: true },
      { isFullLoading: false },
      { isFullLoading: false, streamedAddresses: [] },
      { isFullLoading: true },
    ];
    const expectedCompleteness = [false, false, true, false];
    updates.forEach((update, index) => {
      getApiUpdateHandler()(global, actions, {
        type: 'updateNfts', accountId: ACCOUNT_ID, chain: 'ton', nfts: [], ...update,
      });
      global = (setGlobal as jest.Mock).mock.calls.at(-1)![0] as GlobalState;
      expect(global.byAccountId[ACCOUNT_ID].nfts?.isFullLoadCompleteByChain?.ton).toBe(expectedCompleteness[index]);
    });
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

  it('replaces a stored NFT without metadata with the batch version', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.byAccountId[ACCOUNT_ID].nfts = {
      byAddress: { [NFT_ADDRESS]: makeNft({ isMetadataMissing: true }) },
      orderedAddresses: [NFT_ADDRESS],
    };

    const nft = dispatchUpdateNfts(global, [makeNft({ name: 'From batch' })], true);

    expect(nft).toMatchObject({ name: 'From batch' });
    expect(nft.isMetadataMissing).toBeUndefined();
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

describe('migrateLegacyCoreApplication api update', () => {
  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
    jest.mocked(callApi).mockClear();
    jest.mocked(callApiWithThrow).mockReset().mockResolvedValue(undefined);
    jest.mocked(persistCache).mockClear();
    jest.mocked(persistCache).mockReturnValue(true);
    jest.mocked(setGlobal).mockImplementation((global) => {
      jest.mocked(getGlobal).mockReturnValue(global);
    });
  });

  function makeEmptyGlobal(): GlobalState {
    return {
      auth: {}, appState: AppState.Auth,
      accounts: { byId: {} },
      byAccountId: {},
      settings: { byAccountId: {}, isTestnet: false },
      pushNotifications: { enabledAccounts: [] },
    } as unknown as GlobalState;
  }

  const update = {
    type: 'migrateLegacyCoreApplication',
    accounts: [
      { accountId: '0-ton-testnet', address: 'kQtest' },
    ],
    currentAccountId: '0-ton-testnet',
  } as ApiUpdate;

  async function dispatch(global: GlobalState, event: ApiUpdate = update) {
    const actions = {
      afterSignIn: jest.fn(),
      showError: jest.fn(),
      switchAccount: jest.fn(),
    };
    getApiUpdateHandler()(global, actions, event);
    await new Promise((resolve) => setTimeout(resolve, 0));
    const updatedGlobal = (setGlobal as jest.Mock).mock.calls.at(-1)?.[0] as GlobalState | undefined;
    return { actions, updatedGlobal: updatedGlobal ?? global };
  }

  it('creates only the original network wallet', async () => {
    const { actions, updatedGlobal } = await dispatch(makeEmptyGlobal());

    expect(Object.keys(updatedGlobal.accounts!.byId)).toEqual(['0-ton-testnet']);
    expect(updatedGlobal.accounts?.byId['0-ton-testnet']).toMatchObject({
      type: 'mnemonic', byChain: { ton: { address: 'kQtest' } },
    });
    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(actions.afterSignIn).not.toHaveBeenCalled();
    getApiUpdateHandler()(updatedGlobal, actions, { type: 'legacyCoreMigrationReady', accountId: '0-ton-testnet' });
    expect(actions.afterSignIn).toHaveBeenCalled();
    expect(updatedGlobal.isLegacyCoreMigrationCompleted).toBe(true);
    expect(callApi).not.toHaveBeenCalled();
  });

  it('does not resurrect a deleted wallet or override later preferences after durable UI completion', async () => {
    const first = (await dispatch(makeEmptyGlobal())).updatedGlobal;
    delete first.accounts!.byId['0-ton-testnet'];
    first.accounts!.byId['2-ton-mainnet'] = {
      title: 'Later wallet', type: 'mnemonic', byChain: { ton: { address: 'EQlater' } },
    };
    first.currentAccountId = '2-ton-mainnet';
    (setGlobal as jest.Mock).mockClear();

    const { actions, updatedGlobal } = await dispatch(first);

    expect(Object.keys(updatedGlobal.accounts!.byId)).toEqual([
      '2-ton-mainnet',
    ]);
    expect(actions.showError).not.toHaveBeenCalled();
    expect(actions.switchAccount).not.toHaveBeenCalled();
    expect(actions.afterSignIn).not.toHaveBeenCalled();
    expect(callApi).not.toHaveBeenCalled();
  });

  it('keeps an existing UI account name and preferences when completing the handoff', async () => {
    const global = makeEmptyGlobal();
    const account = { title: 'My testnet savings', type: 'mnemonic' as const, byChain: { ton: { address: 'kQtest' } } };
    global.accounts!.byId['0-ton-testnet'] = account;
    global.currentAccountId = '0-ton-testnet';
    global.settings.byAccountId['0-ton-testnet'] = { pinnedSlugs: ['custom-token'] };
    const { actions, updatedGlobal } = await dispatch(global);
    expect(updatedGlobal.accounts!.byId['0-ton-testnet']).toEqual(account);
    expect(updatedGlobal.settings.byAccountId['0-ton-testnet']?.pinnedSlugs).toEqual(['custom-token']);
    expect(actions.switchAccount).not.toHaveBeenCalled();
    expect(updatedGlobal.isLegacyCoreMigrationCompleted).toBe(true);
  });

  it('repairs a missing original wallet while keeping the selected existing wallet', async () => {
    const global = makeEmptyGlobal();
    const current = { title: 'Selected wallet', type: 'mnemonic' as const, byChain: { ton: { address: 'EQother' } } };
    global.accounts!.byId['2-ton-mainnet'] = current;
    global.currentAccountId = '2-ton-mainnet';
    global.settings.byAccountId['2-ton-mainnet'] = { pinnedSlugs: ['custom-token'] };

    const { actions, updatedGlobal } = await dispatch(global, {
      type: 'migrateLegacyCoreApplication', currentAccountId: '0-ton-testnet',
      accounts: [
        { accountId: '0-ton-testnet', address: 'kQtest' },
        { accountId: '2-ton-mainnet', address: 'EQother' },
      ],
    });

    expect(updatedGlobal.accounts!.byId['0-ton-testnet']).toBeDefined();
    expect(updatedGlobal.accounts!.byId['2-ton-mainnet']).toEqual(current);
    expect(updatedGlobal.currentAccountId).toBe('2-ton-mainnet');
    expect(updatedGlobal.settings.isTestnet).toBe(false);
    expect(updatedGlobal.settings.byAccountId['2-ton-mainnet']?.pinnedSlugs).toEqual(['custom-token']);
    expect(actions.switchAccount).not.toHaveBeenCalled();
    expect(actions.afterSignIn).not.toHaveBeenCalled();
    expect(persistCache).toHaveBeenCalled();
    expect(callApi).not.toHaveBeenCalled();
  });

  it('activates the original wallet when the cached selection points at a missing account', async () => {
    const global = makeEmptyGlobal();
    global.accounts!.byId['0-ton-testnet'] = {
      title: 'Recovered wallet', type: 'mnemonic', byChain: { ton: { address: 'kQtest' } },
    };
    global.currentAccountId = '9-ton-mainnet';

    const { actions, updatedGlobal } = await dispatch(global);

    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(actions.afterSignIn).not.toHaveBeenCalled();
    getApiUpdateHandler()(updatedGlobal, actions, { type: 'legacyCoreMigrationReady', accountId: '0-ton-testnet' });
    expect(actions.afterSignIn).toHaveBeenCalled();
  });

  it('does not replace a conflicting UI account', async () => {
    const global = makeEmptyGlobal();
    global.accounts!.byId['0-ton-testnet'] = {
      title: 'Different wallet', type: 'mnemonic', byChain: { ton: { address: 'EQdifferent' } },
    };

    const { actions } = await dispatch(global);

    expect(setGlobal).not.toHaveBeenCalled();
    expect(actions.showError).toHaveBeenCalled();
    expect(actions.switchAccount).not.toHaveBeenCalled();
  });

  it('does not acknowledge the API migration until the repaired UI cache is durable', async () => {
    jest.mocked(persistCache).mockReturnValue(false);

    const { updatedGlobal } = await dispatch(makeEmptyGlobal());

    expect(callApi).not.toHaveBeenCalled();
    expect(updatedGlobal.isLegacyCoreMigrationCompleted).toBeUndefined();
  });

  it('leaves SDK confirmation to the initialization barrier after persisting UI completion', async () => {
    const { updatedGlobal } = await dispatch(makeEmptyGlobal());

    expect(persistCache).toHaveBeenCalled();
    expect(updatedGlobal.isLegacyCoreMigrationCompleted).toBe(true);
    expect(callApi).not.toHaveBeenCalled();
  });

  it('rolls back the in-memory marker when UI cache persistence throws', async () => {
    jest.mocked(persistCache).mockImplementationOnce(() => {
      throw new Error('quota exceeded');
    });

    const { actions, updatedGlobal } = await dispatch(makeEmptyGlobal());

    expect(updatedGlobal.isLegacyCoreMigrationCompleted).toBeUndefined();
    expect(callApi).not.toHaveBeenCalled();
    expect(actions.showError).toHaveBeenCalledWith({ error: 'Migration error' });
  });

  it.each(['removed', 'authChanged'])('ignores a late restore signal when the handoff was %s', async (change) => {
    const { actions, updatedGlobal } = await dispatch(makeEmptyGlobal());
    const later = change === 'removed' ? makeEmptyGlobal() : { ...updatedGlobal, auth: { ...updatedGlobal.auth } };
    getApiUpdateHandler()(later, actions, { type: 'legacyCoreMigrationReady', accountId: '0-ton-testnet' });
    expect(actions.afterSignIn).not.toHaveBeenCalled();
  });

  it('normalizes the network even when the account ID was already selected', async () => {
    const global = makeEmptyGlobal();
    global.currentAccountId = '0-ton-testnet';
    global.accounts!.byId['0-ton-testnet'] = {
      title: 'Testnet', type: 'mnemonic', byChain: { ton: { address: 'kQtest' } },
    };
    const { updatedGlobal } = await dispatch(global);
    expect(updatedGlobal.settings.isTestnet).toBe(true);
    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(persistCache).toHaveBeenCalled();
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

  it('clears a stale isNftBuyingDisabled persisted by an older build', () => {
    const global = {
      restrictions: { isNftBuyingDisabled: true },
      settings: { byAccountId: {} },
    } as unknown as GlobalState;

    const updatedGlobal = dispatchUpdateConfig(global, undefined);

    expect(updatedGlobal.restrictions.isNftBuyingDisabled).toBe(false);
  });
});

describe('updateAccount api update', () => {
  const ACCOUNT_ID = '0-ton-mainnet';

  it('stores the TON wallet version on an existing chain', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.accounts!.byId[ACCOUNT_ID] = { ...global.accounts!.byId[ACCOUNT_ID], byChain: { ton: { address: 'UQ1' } } };
    (setGlobal as jest.Mock).mockClear();

    getApiUpdateHandler()(global, {}, { type: 'updateAccount', accountId: ACCOUNT_ID, chain: 'ton', version: 'W5' });

    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    expect((updatedGlobal as GlobalState).accounts!.byId[ACCOUNT_ID].byChain.ton)
      .toEqual({ address: 'UQ1', version: 'W5' });
  });

  it('stores the TON wallet version on a chain added to the account', () => {
    const global = makeGlobal(ACCOUNT_ID);
    global.accounts!.byId[ACCOUNT_ID] = { ...global.accounts!.byId[ACCOUNT_ID], byChain: {} };
    (setGlobal as jest.Mock).mockClear();

    getApiUpdateHandler()(global, {}, {
      type: 'updateAccount', accountId: ACCOUNT_ID, chain: 'ton', address: 'UQ1', version: 'W5',
    });

    const [updatedGlobal] = (setGlobal as jest.Mock).mock.calls.at(-1)!;
    expect((updatedGlobal as GlobalState).accounts!.byId[ACCOUNT_ID].byChain.ton)
      .toEqual({ address: 'UQ1', version: 'W5' });
  });
});
