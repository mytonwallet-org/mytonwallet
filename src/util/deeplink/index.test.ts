import type { GlobalState } from '../../global/types';

import { TON_USDT, TON_USDT_MAINNET_SLUG, TONCOIN } from '../../config';
import { INITIAL_STATE } from '../../global/initialState';
import { parseTonDeeplink } from './index';

// Test constants
const TEST_TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TEST_DNS_NAME = 'testmytonwallet.ton';
const TEST_BIN_PAYLOAD = 'te6ccgEBAQEANwAAaV0r640BleSq4Ql3m5OrdlSApYTNRMdDGUFXwTpwZ1oe1G8cPlS_Zym8CwoAdO4mWSned-Fg';
const TEST_STATE_INIT = 'te6ccgEBAgEACwACATQBAQAI_____w\\=\\=';
const TEST_COMMENT = 'MyTonWallet';
const TEST_AMOUNT = 1n;

// Test timestamps
const EXPIRED_TIMESTAMP = 946684800; // 1 January 2000 (definitely in the past)
const VALID_TIMESTAMP = 2147483647; // 19 January 2038 (definitely in the future)

// Mock global state for testing
const createMockGlobalState = (): GlobalState => {
  const mockState: GlobalState = {
    ...INITIAL_STATE,
    currentAccountId: 'test-account-id',
    tokenInfo: {
      bySlug: {
        [TONCOIN.slug]: {
          ...TONCOIN,
          price: 1,
          priceUsd: 1,
          percentChange24h: 1,
        },
        [TON_USDT_MAINNET_SLUG]: {
          ...TON_USDT,
          price: 1,
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
            [TON_USDT_MAINNET_SLUG]: 1000000n, // 1 USDT
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

  return mockState;
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
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT.tokenAddress}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET_SLUG,
        amount: TEST_AMOUNT,
      },
    },
    {
      name: 'parse jetton transfer with binary payload',
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT.tokenAddress}&bin=${TEST_BIN_PAYLOAD}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET_SLUG,
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
      url: `ton://transfer/${TEST_TON_ADDRESS}?amount=1&jetton=${TON_USDT.tokenAddress}&text=${TEST_COMMENT}`,
      expected: {
        toAddress: TEST_TON_ADDRESS,
        tokenSlug: TON_USDT_MAINNET_SLUG,
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
