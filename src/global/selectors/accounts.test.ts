import type { Account, GlobalState } from '../types';
import { ContentTab } from '../types';

import { selectHasAuth, selectHasPassword, selectIsContentListOpen, selectShouldMigrate } from './accounts';

const MNEMONIC_ACCOUNT = { title: 'Wallet', type: 'mnemonic', byChain: {} } as unknown as Account;
const HARDWARE_ACCOUNT = { title: 'Ledger', type: 'hardware', byChain: {} } as unknown as Account;

function buildGlobal(accounts: Record<string, Account>, authTypes?: GlobalState['authTypes']): GlobalState {
  return {
    authTypes,
    currentAccountId: Object.keys(accounts)[0],
    settings: { isTestnet: false },
    accounts: { byId: accounts },
  } as unknown as GlobalState;
}

describe('auth-state selectors', () => {
  it('sees no password in an empty wallet', () => {
    const global = buildGlobal({});

    expect(selectHasAuth(global)).toBe(false);
    expect(selectHasPassword(global)).toBe(false);
    expect(selectShouldMigrate(global)).toBe(false);
  });

  it('sees a password behind a not-yet-migrated mnemonic account', () => {
    const global = buildGlobal({ '0-ton-mainnet': MNEMONIC_ACCOUNT });

    expect(selectHasAuth(global)).toBe(false);
    expect(selectHasPassword(global)).toBe(true);
    expect(selectShouldMigrate(global)).toBe(true);
  });

  it('sees a password once the Enclave is provisioned', () => {
    const global = buildGlobal({ '0-ton-mainnet': MNEMONIC_ACCOUNT }, ['passcode']);

    expect(selectHasAuth(global)).toBe(true);
    expect(selectHasPassword(global)).toBe(true);
    expect(selectShouldMigrate(global)).toBe(false);
  });

  // A hardware-only wallet never had a password, so it must neither be asked for one nor sent into a
  // migration that would find nothing to decrypt.
  it('sees no password in a hardware-only wallet', () => {
    const global = buildGlobal({ '0-ton-mainnet': HARDWARE_ACCOUNT });

    expect(selectHasPassword(global)).toBe(false);
    expect(selectShouldMigrate(global)).toBe(false);
  });
});

describe('selectIsContentListOpen', () => {
  function getIsOpen(accountState: AnyLiteral) {
    const global = { currentAccountId: 'id', byAccountId: { id: accountState } } as unknown as GlobalState;

    return selectIsContentListOpen(global);
  }

  it('keeps the list under a token opened from it', () => {
    expect(getIsOpen({
      activeContentTab: ContentTab.Activity,
      activityReturnContentTab: ContentTab.Assets,
      currentTokenSlug: 'toncoin',
    })).toBe(true);
  });

  it('keeps the home screen under a token opened from it', () => {
    expect(getIsOpen({
      activeContentTab: ContentTab.Activity,
      activityReturnContentTab: ContentTab.Overview,
      currentTokenSlug: 'toncoin',
    })).toBe(false);
  });

  it('opens for a collection on the home tab', () => {
    expect(getIsOpen({
      activeContentTab: ContentTab.Overview,
      nfts: { currentCollection: { chain: 'ton', address: 'address' } },
    })).toBe(true);
  });
});
