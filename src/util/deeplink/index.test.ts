import { getActions, getGlobal } from '../../global';

import type { GlobalState } from '../../global/types';
import { ActiveTab, ContentTab } from '../../global/types';

import {
  DEFAULT_SWAP_AMOUNT,
  DEFAULT_SWAP_SECOND_TOKEN_SLUG,
  TON_USDT_MAINNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRC20_USDT_TESTNET,
  TRX,
} from '../../config';
import { INITIAL_STATE } from '../../global/initialState';
import { getChainConfig } from '../chain';
import { openUrl } from '../openUrl';
import { parseTonDeeplink, processDeeplink, processSelfDeeplink } from './index';

import { getIsLandscape } from '../../hooks/useDeviceScreen';

// Mock modules
jest.mock('../../global', () => ({
  getActions: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

jest.mock('../../api', () => ({
  callApi: jest.fn(),
}));

jest.mock('../capacitor', () => ({
  switchToAir: jest.fn(),
}));

jest.mock('../openUrl', () => ({
  openUrl: jest.fn(),
}));

jest.mock('../renderPromise', () => ({
  waitRender: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../../hooks/useDeviceScreen', () => ({
  getIsLandscape: jest.fn().mockReturnValue(false),
  getIsPortrait: jest.fn().mockReturnValue(true),
}));

// Test constants
const TEST_TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TEST_TRON_ADDRESS = 'TBvwz11CKdgBymTtF7Q6UfhGWQyEqNrodT';
const TEST_DNS_NAME = 'testmytonwallet.ton';
const TEST_BIN_PAYLOAD = 'te6ccgEBAQEANwAAaV0r640BleSq4Ql3m5OrdlSApYTNRMdDGUFXwTpwZ1oe1G8cPlS_Zym8CwoAdO4mWSned-Fg';
const TEST_STATE_INIT = 'te6ccgEBAgEACwACATQBAQAI_____w\\=\\=';
const TEST_COMMENT = 'MyTonWallet';
const TEST_AMOUNT = 1n;
const TEST_TRON_AMOUNT_77 = 77000000n; // 77 TRX in smallest units (6 decimals)

// Test timestamps
const EXPIRED_TIMESTAMP = 946684800; // 1 January 2000 (definitely in the past)
const VALID_TIMESTAMP = 2147483647; // 19 January 2038 (definitely in the future)

// Mock global state for testing
const createMockGlobalState = (): GlobalState => {
  return {
    ...INITIAL_STATE,
    currentAccountId: 'test-account-id',
    accounts: {
      byId: {
        'test-account-id': {
          title: 'Test Account',
          type: 'mnemonic',
          byChain: {
            ton: {
              address: 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S',
            },
            tron: {
              address: TEST_TRON_ADDRESS,
            },
          },
        },
      },
    },
    tokenInfo: {
      bySlug: {
        [TONCOIN.slug]: {
          ...TONCOIN,
          priceUsd: 1,
          percentChange24h: 1,
        },
        [TON_USDT_MAINNET.slug]: {
          ...TON_USDT_MAINNET,
          priceUsd: 1,
          percentChange24h: 1,
        },
        [TRX.slug]: {
          ...TRX,
          priceUsd: 1,
          percentChange24h: 1,
        },
        [TRC20_USDT_MAINNET.slug]: {
          ...TRC20_USDT_MAINNET,
          priceUsd: 1,
          percentChange24h: 1,
        },
        [TRC20_USDT_TESTNET.slug]: {
          ...TRC20_USDT_TESTNET,
          priceUsd: 1,
          percentChange24h: 1,
        },
      },
    },
    byAccountId: {
      'test-account-id': {
        balances: {
          bySlug: {
            [TONCOIN.slug]: 1000000000n, // 1 TON
            [TON_USDT_MAINNET.slug]: 1000000n, // 1 USDT
            [TRX.slug]: 1000000n, // 1 TRX
            [TRC20_USDT_MAINNET.slug]: 1000000n, // 1 USDT TRC20
          },
        },
        nfts: {
          byAddress: {},
        },
      },
    },
    settings: {
      ...INITIAL_STATE.settings,
      isTestnet: false,
      byAccountId: {
        'test-account-id': {},
      },
    },
  };
};

describe('parseTonDeeplink', () => {
  it.each([
    {
      name: 'parse TON transfer with binary payload',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&bin=${TEST_BIN_PAYLOAD}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        binPayload: TEST_BIN_PAYLOAD,
      },
    },
    {
      name: 'return error for expired transfer link',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&exp=${EXPIRED_TIMESTAMP}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        error: '$transfer_link_expired',
      },
    },
    {
      name: 'parse transfer to DNS domain name',
      url: `ton://transfer/${TEST_DNS_NAME}?amount=1`,
      expected: {
        toAddress: TEST_DNS_NAME,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
      },
    },
    {
      name: 'parse jetton token transfer',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT_MAINNET.tokenAddress}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET.slug,
        amount: TEST_AMOUNT,
      },
    },
    {
      name: 'parse jetton transfer with binary payload',
      url:
        `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT_MAINNET.tokenAddress}&bin=${TEST_BIN_PAYLOAD}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET.slug,
        amount: TEST_AMOUNT,
        binPayload: TEST_BIN_PAYLOAD,
      },
    },
    {
      name: 'parse transfer with valid expiration timestamp',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&exp=${VALID_TIMESTAMP}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
      },
    },
    {
      name: 'parse transfer with state initialization data',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&init=${TEST_STATE_INIT}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        stateInit: TEST_STATE_INIT,
      },
    },
    {
      name: 'parse jetton transfer with text comment',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT_MAINNET.tokenAddress}&text=${TEST_COMMENT}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET.slug,
        amount: TEST_AMOUNT,
        comment: TEST_COMMENT,
      },
    },
    {
      name: 'parse TON transfer with text comment',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&text=${TEST_COMMENT}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        comment: TEST_COMMENT,
      },
    },
    {
      name: 'parse transfer with state initialization and binary payload',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&init=${TEST_STATE_INIT}&bin=${TEST_BIN_PAYLOAD}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        stateInit: TEST_STATE_INIT,
        binPayload: TEST_BIN_PAYLOAD,
      },
    },
    {
      name: 'parse transfer with state initialization and text comment',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&init=${TEST_STATE_INIT}&text=${TEST_COMMENT}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        stateInit: TEST_STATE_INIT,
        comment: TEST_COMMENT,
      },
    },
    {
      name: 'return error when both text and binary parameters are provided',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&text=${TEST_COMMENT}&bin=${TEST_BIN_PAYLOAD}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TONCOIN.slug,
        amount: TEST_AMOUNT,
        comment: TEST_COMMENT,
        binPayload: TEST_BIN_PAYLOAD,
        error: '$transfer_text_and_bin_exclusive',
      },
    },
    {
      name: 'return error when unsupported parameters are provided',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&unsupported=value&another=param`,
      expected: {
        error: '$unsupported_deeplink_parameter',
      },
    },
  ])('should $name', ({ url, expected }) => {
    const global = createMockGlobalState();
    const result = parseTonDeeplink(url, global);
    expect(result).toEqual(expected);
  });
});

describe('processSelfDeeplink', () => {
  let mockActions: Record<string, jest.Mock>;
  let mockGlobal: GlobalState;

  beforeEach(() => {
    // Reset all mocks before each test
    jest.clearAllMocks();

    // Setup mock actions
    mockActions = {
      startSwap: jest.fn(),
      showError: jest.fn(),
      openOnRampWidgetModal: jest.fn(),
      startStaking: jest.fn(),
      startTransfer: jest.fn(),
      setLandscapeActionsActiveTabIndex: jest.fn(),
      closeSettings: jest.fn(),
      openExplore: jest.fn(),
      setActiveContentTab: jest.fn(),
      openReceiveModal: jest.fn(),
      openTemporaryViewAccount: jest.fn(),
    };

    // Setup mock global state
    mockGlobal = createMockGlobalState();

    // Setup getActions and getGlobal mocks
    (getActions as jest.Mock).mockReturnValue(mockActions);
    (getGlobal as jest.Mock).mockReturnValue(mockGlobal);
  });

  describe('Swap command', () => {
    it('should start swap with default parameters using mtw:// protocol', async () => {
      const result = await processSelfDeeplink('mtw://swap');

      expect(result).toBe(true);
      expect(mockActions.startSwap).toHaveBeenCalledWith({
        tokenInSlug: TONCOIN.slug,
        tokenOutSlug: DEFAULT_SWAP_SECOND_TOKEN_SLUG,
        amountIn: DEFAULT_SWAP_AMOUNT,
      });
      expect(mockActions.showError).not.toHaveBeenCalled();
    });

    it('should start swap with custom parameters using https://my.tt protocol', async () => {
      const result = await processSelfDeeplink('https://my.tt/swap?in=ton-usdt&out=toncoin&amount=50');

      expect(result).toBe(true);
      expect(mockActions.startSwap).toHaveBeenCalledWith({
        tokenInSlug: 'ton-usdt',
        tokenOutSlug: TONCOIN.slug,
        amountIn: '50',
      });
    });

    it('should show error when swap is requested in testnet', async () => {
      mockGlobal.settings.isTestnet = true;

      const result = await processSelfDeeplink('mtw://swap');

      expect(result).toBe(true);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: 'Swap is not supported in Testnet.',
      });
      expect(mockActions.startSwap).not.toHaveBeenCalled();
    });

    it('should show error when swap is requested with Ledger account', async () => {
      mockGlobal.accounts!.byId['test-account-id'].type = 'hardware';

      const result = await processSelfDeeplink('mtw://swap');

      expect(result).toBe(true);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: 'Swap is not yet supported by Ledger.',
      });
      expect(mockActions.startSwap).not.toHaveBeenCalled();
    });
  });

  describe('Buy with crypto command', () => {
    it('should start swap for buying with default parameters', async () => {
      const result = await processSelfDeeplink('mtw://buy-with-crypto');
      const { nativeToken, buySwap: defaultBuySwap } = getChainConfig('ton');

      expect(result).toBe(true);
      expect(mockActions.startSwap).toHaveBeenCalledWith({
        tokenInSlug: defaultBuySwap.tokenInSlug,
        tokenOutSlug: nativeToken.slug,
        amountIn: defaultBuySwap.amountIn,
      });
    });

    it('should start swap with custom parameters for buying', async () => {
      const result = await processSelfDeeplink(
        'https://go.mytonwallet.org/buy-with-crypto?in=ton-usdt&out=toncoin&amount=200',
      );

      expect(result).toBe(true);
      expect(mockActions.startSwap).toHaveBeenCalledWith({
        tokenInSlug: 'ton-usdt',
        tokenOutSlug: TONCOIN.slug,
        amountIn: '200',
      });
    });

    it('should show error when buy-with-crypto is requested in testnet', async () => {
      mockGlobal.settings.isTestnet = true;

      const result = await processSelfDeeplink('mtw://buy-with-crypto');

      expect(result).toBe(true);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: 'Swap is not supported in Testnet.',
      });
    });
  });

  describe('Buy with card command', () => {
    it('should open on-ramp widget modal', async () => {
      const result = await processSelfDeeplink('mtw://buy-with-card');

      expect(result).toBe(true);
      expect(mockActions.openOnRampWidgetModal).toHaveBeenCalledWith({ chain: 'ton' });
    });

    it('should show error when buy-with-card is requested in testnet', async () => {
      mockGlobal.settings.isTestnet = true;

      const result = await processSelfDeeplink('https://my.tt/buy-with-card');

      expect(result).toBe(true);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: 'Buying with card is not supported in Testnet.',
      });
      expect(mockActions.openOnRampWidgetModal).not.toHaveBeenCalled();
    });
  });

  describe('Stake command', () => {
    it('should start staking', async () => {
      const result = await processSelfDeeplink('mtw://stake');

      expect(result).toBe(true);
      expect(mockActions.startStaking).toHaveBeenCalled();
    });

    it('should show error when staking is requested in testnet', async () => {
      mockGlobal.settings.isTestnet = true;

      const result = await processSelfDeeplink('https://my.tt/stake');

      expect(result).toBe(true);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: 'Staking is not supported in Testnet.',
      });
      expect(mockActions.startStaking).not.toHaveBeenCalled();
    });
  });

  describe('Checkin command', () => {
    it('should open checkin URL without referral code', async () => {
      const result = await processSelfDeeplink('mtw://r/');

      expect(result).toBe(true);
      expect(openUrl).toHaveBeenCalledWith('https://checkin.mytonwallet.org');
    });

    it('should open checkin URL with referral code', async () => {
      const result = await processSelfDeeplink('https://my.tt/r/ABC123');

      expect(result).toBe(true);
      expect(openUrl).toHaveBeenCalledWith('https://checkin.mytonwallet.org?r=ABC123');
    });
  });

  describe('Giveaway command', () => {
    it('should open giveaway URL without giveaway ID', async () => {
      const result = await processSelfDeeplink('mtw://giveaway/');

      expect(result).toBe(true);
      expect(openUrl).toHaveBeenCalledWith('https://giveaway.mytonwallet.io');
    });

    it('should open giveaway URL with giveaway ID', async () => {
      const result = await processSelfDeeplink('https://go.mytonwallet.org/giveaway/GIVEAWAY123');

      expect(result).toBe(true);
      expect(openUrl).toHaveBeenCalledWith('https://giveaway.mytonwallet.io?giveawayId=GIVEAWAY123');
    });
  });

  describe('Receive command', () => {
    it('should open receive modal in portrait mode', async () => {
      const result = await processSelfDeeplink('mtw://receive');

      expect(result).toBe(true);
      expect(mockActions.openReceiveModal).toHaveBeenCalled();
      expect(mockActions.setLandscapeActionsActiveTabIndex).not.toHaveBeenCalled();
    });

    it('should set landscape tab in landscape mode', async () => {
      (getIsLandscape as jest.Mock).mockReturnValue(true);

      const result = await processSelfDeeplink('https://my.tt/receive');

      expect(result).toBe(true);
      expect(mockActions.setLandscapeActionsActiveTabIndex).toHaveBeenCalledWith({ index: ActiveTab.Receive });
      expect(mockActions.openReceiveModal).not.toHaveBeenCalled();
    });
  });

  describe('Explore command', () => {
    it('should open explore tab', async () => {
      const result = await processSelfDeeplink('mtw://explore');

      expect(result).toBe(true);
      expect(mockActions.closeSettings).toHaveBeenCalled();
      expect(mockActions.openExplore).toHaveBeenCalled();
      expect(mockActions.setActiveContentTab).toHaveBeenCalledWith({ tab: ContentTab.Explore });
    });

    it('should open explore tab with specific host', async () => {
      mockGlobal.exploreData = {
        categories: [],
        sites: [
          {
            url: 'https://example.com',
            name: 'Example',
            icon: '',
            manifestUrl: '',
            description: '',
            canBeRestricted: false,
            isExternal: false,
          },
        ],
      };

      const result = await processSelfDeeplink('https://my.tt/explore/example.com');

      expect(result).toBe(true);
      expect(mockActions.openExplore).toHaveBeenCalled();
      expect(openUrl).toHaveBeenCalledWith('https://example.com');
    });
  });

  describe('View command', () => {
    it('should open temporary view account with single address', async () => {
      const result = await processSelfDeeplink(`mtw://view?ton=${TEST_TON_ADDRESS}`);

      expect(result).toBe(true);
      expect(mockActions.openTemporaryViewAccount).toHaveBeenCalledWith({
        addressByChain: {
          ton: TEST_TON_ADDRESS,
        },
      });
    });

    it('should open temporary view account with multiple addresses', async () => {
      const result = await processSelfDeeplink(`https://my.tt/view?ton=${TEST_TON_ADDRESS}&tron=${TEST_TRON_ADDRESS}`);

      expect(result).toBe(true);
      expect(mockActions.openTemporaryViewAccount).toHaveBeenCalled();
      const callArg = mockActions.openTemporaryViewAccount.mock.calls[0][0];
      expect(callArg.addressByChain.ton).toBeDefined();
      expect(callArg.addressByChain.tron).toBeDefined();
    });

    it('should show error when no valid addresses provided', async () => {
      const result = await processSelfDeeplink('mtw://view');

      expect(result).toBe(false);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: '$no_valid_view_addresses',
      });
    });

    it('should show error when all provided addresses are invalid', async () => {
      const result = await processSelfDeeplink('mtw://view?ton=invalid-address');

      expect(result).toBe(false);
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: '$no_valid_view_addresses',
      });
    });

    it('should decode URI-encoded addresses', async () => {
      const encodedUrl = `https://my.tt/view?ton=${encodeURIComponent(TEST_TON_ADDRESS)}`;
      const result = await processSelfDeeplink(encodedUrl);

      expect(result).toBe(true);
      expect(mockActions.openTemporaryViewAccount).toHaveBeenCalledWith({
        addressByChain: {
          ton: TEST_TON_ADDRESS,
        },
      });
    });
  });

  describe('Transfer command', () => {
    it('should process transfer deeplink', async () => {
      const result = await processSelfDeeplink(`mtw://transfer/${TEST_TON_ADDRESS}?amount=1`);

      expect(result).toBe(true);
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          toAddress: TEST_TON_ADDRESS,
          tokenSlug: TONCOIN.slug,
          amount: 1n,
          isPortrait: true,
        }),
      );
    });

    it('should process transfer with https://my.tt protocol', async () => {
      const result = await processSelfDeeplink(`https://my.tt/transfer/${TEST_TON_ADDRESS}?amount=5&text=Hello`);

      expect(result).toBe(true);
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          toAddress: TEST_TON_ADDRESS,
          tokenSlug: TONCOIN.slug,
          amount: 5n,
          comment: 'Hello',
        }),
      );
    });
  });

  describe('Air command', () => {
    it('should return false when not in Capacitor environment', async () => {
      // IS_CAPACITOR is false by default in tests
      const result = await processSelfDeeplink('mtw://air');

      expect(result).toBe(false);
    });
  });

  describe('Invalid deeplinks', () => {
    it('should return false for unknown commands', async () => {
      const result = await processSelfDeeplink('mtw://unknown-command');

      expect(result).toBe(false);
    });

    it('should return false for malformed URLs', async () => {
      const result = await processSelfDeeplink('not-a-valid-url');

      expect(result).toBe(false);
    });

    it('should handle errors gracefully', async () => {
      (getGlobal as jest.Mock).mockImplementation(() => {
        throw new Error('Test error');
      });

      const result = await processSelfDeeplink('mtw://swap');

      expect(result).toBe(false);
    });
  });

  describe('Protocol variations', () => {
    it('should handle mtw:// protocol', async () => {
      const result = await processSelfDeeplink('mtw://stake');

      expect(result).toBe(true);
      expect(mockActions.startStaking).toHaveBeenCalled();
    });

    it('should handle https://my.tt protocol', async () => {
      const result = await processSelfDeeplink('https://my.tt/stake');

      expect(result).toBe(true);
      expect(mockActions.startStaking).toHaveBeenCalled();
    });

    it('should handle https://go.mytonwallet.org protocol', async () => {
      const result = await processSelfDeeplink('https://go.mytonwallet.org/stake');

      expect(result).toBe(true);
      expect(mockActions.startStaking).toHaveBeenCalled();
    });

    it('should convert http:// to https://', async () => {
      const result = await processSelfDeeplink('http://my.tt/stake');

      expect(result).toBe(true);
      expect(mockActions.startStaking).toHaveBeenCalled();
    });
  });
});

describe('processDeeplink TRON deeplinks', () => {
  let mockActions: Record<string, jest.Mock>;
  let mockGlobal: GlobalState;

  beforeEach(() => {
    jest.clearAllMocks();

    mockActions = {
      startSwap: jest.fn(),
      showError: jest.fn(),
      openOnRampWidgetModal: jest.fn(),
      startStaking: jest.fn(),
      openReceiveModal: jest.fn(),
      closeSettings: jest.fn(),
      openExplore: jest.fn(),
      setActiveContentTab: jest.fn(),
      openTemporaryViewAccount: jest.fn(),
      setLandscapeActionsActiveTabIndex: jest.fn(),
      startTransfer: jest.fn(),
    };

    mockGlobal = createMockGlobalState();

    (getActions as jest.Mock).mockReturnValue(mockActions);
    (getGlobal as jest.Mock).mockReturnValue(mockGlobal);
  });

  describe('TRON (tron:) deeplinks', () => {
    it.each([
      {
        name: 'parse TRX transfer with amount',
        url: `tron:${TEST_TRON_ADDRESS}?amount=77`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRX.slug,
          amount: TEST_TRON_AMOUNT_77,
        },
      },
      {
        name: 'parse TRX transfer without amount',
        url: `tron:${TEST_TRON_ADDRESS}`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRX.slug,
        },
      },
      {
        name: 'parse TRX transfer with zero amount',
        url: `tron:${TEST_TRON_ADDRESS}?amount=0`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRX.slug,
          amount: 0n,
        },
      },
      {
        name: 'parse TRX transfer with decimal amount',
        url: `tron:${TEST_TRON_ADDRESS}?amount=1.5`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRX.slug,
          amount: 1500000n, // 1.5 TRX
        },
      },
    ])('$name', async ({ url, expected }) => {
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.showError).not.toHaveBeenCalled();

      const expectedMatcher: Record<string, unknown> = {
        toAddress: expected.toAddress,
        tokenSlug: expected.tokenSlug,
      };

      if ('amount' in expected) {
        expectedMatcher.amount = expected.amount;
      }

      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining(expectedMatcher),
      );
    });

    it('should handle invalid TRON address', async () => {
      const url = 'tron:invalid-address?amount=1';
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.showError).not.toHaveBeenCalled();
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          tokenSlug: TRX.slug,
          amount: 1000000n,
        }),
      );
    });

    it('should process TON deeplink correctly (not a TRON URL)', async () => {
      const url = `ton://transfer/${TEST_TON_ADDRESS}?amount=1`;
      const result = await processDeeplink(url);

      expect(result).toBe(true); // TON deeplinks are processed successfully
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          toAddress: TEST_TON_ADDRESS,
          tokenSlug: TONCOIN.slug,
          amount: TEST_AMOUNT,
        }),
      );
    });
  });

  describe('Tether (tether:) deeplinks', () => {
    it.each([
      {
        name: 'parse USDT TRC20 transfer with amount (mainnet)',
        url: `tether:${TEST_TRON_ADDRESS}?amount=100`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRC20_USDT_MAINNET.slug,
          amount: 100000000n, // 100 USDT
        },
      },
      {
        name: 'parse USDT TRC20 transfer without amount (mainnet)',
        url: `tether:${TEST_TRON_ADDRESS}`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRC20_USDT_MAINNET.slug,
        },
      },
      {
        name: 'parse USDT TRC20 transfer with decimal amount (mainnet)',
        url: `tether:${TEST_TRON_ADDRESS}?amount=50.5`,
        expected: {
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRC20_USDT_MAINNET.slug,
          amount: 50500000n, // 50.5 USDT
        },
      },
    ])('$name', async ({ url, expected }) => {
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.showError).not.toHaveBeenCalled();

      const expectedMatcher: Record<string, unknown> = {
        toAddress: expected.toAddress,
        tokenSlug: expected.tokenSlug,
      };

      if ('amount' in expected) {
        expectedMatcher.amount = expected.amount;
      }

      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining(expectedMatcher),
      );
    });

    it('should use testnet USDT when isTestnet is true', async () => {
      mockGlobal.settings.isTestnet = true;
      const url = `tether:${TEST_TRON_ADDRESS}?amount=10`;
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.showError).not.toHaveBeenCalled();
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          toAddress: TEST_TRON_ADDRESS,
          tokenSlug: TRC20_USDT_TESTNET.slug,
          amount: 10000000n,
        }),
      );
    });

    it('should show error for unsupported parameters', async () => {
      const url = `tether:${TEST_TRON_ADDRESS}?amount=1&label=test`;
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.startTransfer).not.toHaveBeenCalled();
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: '$unsupported_deeplink_parameter',
      });
    });

    it('should show error for unsupported parameters in tron: deeplink', async () => {
      const url = `tron:${TEST_TRON_ADDRESS}?amount=1&unsupported=value`;
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.startTransfer).not.toHaveBeenCalled();
      expect(mockActions.showError).toHaveBeenCalledWith({
        error: '$unsupported_deeplink_parameter',
      });
    });

    it('should handle invalid TRON address', async () => {
      const url = 'tether:invalid-address?amount=1';
      const result = await processDeeplink(url);

      expect(result).toBe(true);
      expect(mockActions.showError).not.toHaveBeenCalled();
      expect(mockActions.startTransfer).toHaveBeenCalledWith(
        expect.objectContaining({
          tokenSlug: TRC20_USDT_MAINNET.slug,
          amount: 1000000n,
        }),
      );
    });
  });
});
