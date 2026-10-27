import type { ApiForeignStakingPromotion, ApiInfoBannerPromotion } from '../../api/types';
import type { Account, AccountSettings, AccountState, GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';
import { selectCurrentAccountHomeBanners, selectCurrentAccountStakingBanners } from './banners';

const ACCOUNT_ID = '0-mainnet';

const RESTAKE = buildHomeBanner('foreign-staking:ton');
const SERVER = buildHomeBanner('server-earn');
const FOREIGN = buildStakingBanner('foreign-staking:ton:tonstakers', RESTAKE.id);

describe('selectCurrentAccountHomeBanners', () => {
  it('keeps the SDK order and leaves out the dismissed banners', () => {
    const global = buildGlobal({
      accountState: { banners: { home: [RESTAKE, SERVER], staking: [FOREIGN] } },
      settings: { dismissedHomeBannerIds: [RESTAKE.id] },
    });

    expect(selectCurrentAccountHomeBanners(global)).toEqual([SERVER]);
  });

  it('returns the same array while the inputs stay the same', () => {
    const global = buildGlobal({
      accountState: { banners: { home: [RESTAKE, SERVER], staking: [FOREIGN] } },
      settings: { dismissedHomeBannerIds: [SERVER.id] },
    });

    expect(selectCurrentAccountHomeBanners(global)).toBe(selectCurrentAccountHomeBanners(global));
  });

  it('hides the linked banner only when all its staking banners are unstaked', () => {
    const other = buildStakingBanner('foreign-staking:ton:other', RESTAKE.id);
    const banners = { home: [RESTAKE], staking: [FOREIGN, other] };

    const partly = buildGlobal({ accountState: { banners, submittedForeignStakingIds: [FOREIGN.id] } });
    const fully = buildGlobal({ accountState: { banners, submittedForeignStakingIds: [FOREIGN.id, other.id] } });

    expect(selectCurrentAccountHomeBanners(partly)).toEqual([RESTAKE]);
    expect(selectCurrentAccountHomeBanners(fully)).toBeUndefined();
  });

  it('shows nothing for a view account and on testnet', () => {
    const accountState = { banners: { home: [SERVER], staking: [] } };

    expect(selectCurrentAccountHomeBanners(buildGlobal({ accountState, accountType: 'view' }))).toBeUndefined();
    expect(selectCurrentAccountHomeBanners(buildGlobal({ accountState, isTestnet: true }))).toBeUndefined();
  });
});

describe('selectCurrentAccountStakingBanners', () => {
  it('returns the same array while the inputs stay the same', () => {
    const global = buildGlobal({ accountState: { banners: { home: [RESTAKE], staking: [FOREIGN] } } });

    expect(selectCurrentAccountStakingBanners(global)).toEqual([FOREIGN]);
    expect(selectCurrentAccountStakingBanners(global)).toBe(selectCurrentAccountStakingBanners(global));
  });

  it('leaves out the unstaked banners', () => {
    const global = buildGlobal({
      accountState: { banners: { home: [RESTAKE], staking: [FOREIGN] }, submittedForeignStakingIds: [FOREIGN.id] },
    });

    expect(selectCurrentAccountStakingBanners(global)).toEqual([]);
  });
});

function buildGlobal({
  accountState,
  settings,
  accountType = 'mnemonic',
  isTestnet,
}: {
  accountState: AccountState;
  settings?: AccountSettings;
  accountType?: Account['type'];
  isTestnet?: boolean;
}): GlobalState {
  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: { byId: { [ACCOUNT_ID]: { type: accountType, byChain: {} } as unknown as Account } },
    byAccountId: { [ACCOUNT_ID]: accountState },
    settings: {
      ...INITIAL_STATE.settings,
      isTestnet,
      byAccountId: settings ? { [ACCOUNT_ID]: settings } : {},
    },
  };
}

function buildHomeBanner(id: string): ApiInfoBannerPromotion {
  return {
    id,
    kind: 'infoBanner',
    infoBanner: {
      title: id,
      description: id,
      actionButton: { title: 'Restake Now', onClickAction: 'openEarn' },
    },
  };
}

function buildStakingBanner(id: string, linkedBannerId: string): ApiForeignStakingPromotion {
  return {
    id,
    kind: 'foreignStaking',
    foreignStaking: {
      chain: 'ton',
      providerName: 'tonstakers',
      amount: '0.099',
      symbol: 'GRAM',
      apy: 3,
      stakingApy: 4,
    },
    infoBanner: {
      title: id,
      description: id,
      actionButton: {
        title: 'Unstake',
        onClickAction: 'unstakeForeign',
        chain: 'ton',
        providerName: 'tonstakers',
      },
    },
    linkedBannerId,
  };
}
