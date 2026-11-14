import type { ApiSwapBuildTransactionRequest, ApiSwapEstimateRequest } from '../types';

import { ARBITRUM_USDC_MAINNET, BASE_USDC_MAINNET } from '../../config';
import {
  type BackendSwapEstimate,
  getSwapExecutionQuote,
  normalizeSwapAssetSelection,
  prepareSwapBuildRequest,
  rememberSwapExecutionQuote,
} from './swapExecutionQuote';

const mockSource = { ...BASE_USDC_MAINNET, chain: 'base',
  tokenAddress: BASE_USDC_MAINNET.tokenAddress.toLowerCase() };
const mockDestination = { ...ARBITRUM_USDC_MAINNET, chain: 'arbitrum' };
const OWNER = '0x1111111111111111111111111111111111111111';
const RECIPIENT = '0x2222222222222222222222222222222222222222';

jest.mock('./tokens', () => ({
  getTokenBySlug: (slug: string) => [mockSource, mockDestination].find((token) => token.slug === slug),
  getTokenByAddress: (address: string) => ({
    [mockSource.tokenAddress.toLowerCase()]: mockSource,
    [mockDestination.tokenAddress.toLowerCase()]: mockDestination,
  }[address.toLowerCase()]),
}));

const REQUEST: ApiSwapEstimateRequest = {
  from: mockSource.tokenAddress,
  to: mockDestination.tokenAddress,
  fromAddress: OWNER,
  toAddress: RECIPIENT,
  fromAmount: '100',
  slippage: 1,
};
const ESTIMATE: BackendSwapEstimate = {
  route: 'dex', chain: 'base', dexRouterLabel: 'layerzero',
  from: `base:${BASE_USDC_MAINNET.tokenAddress}`, to: `arbitrum:${mockDestination.tokenAddress}`,
  fromAmount: '100', toAmount: '99', toMinAmount: '98', slippage: 1,
  ourFee: '0', ourFeePercent: 0, ourFeeMode: 'included', networkFee: '0.001', realNetworkFee: '0.001',
  vtNativeFeeBudget: '0.004', swapFee: '0', swapFeePercent: 0, impact: 0, dieselStatus: 'not-available',
};
let clock = Date.now();
beforeEach(() => {
  clock += 6 * 60 * 1000;
  jest.useFakeTimers().setSystemTime(clock);
});
afterEach(() => jest.useRealTimers());

test('the existing app request resolves known assets and binds its unchanged confirmation inside SDK', () => {
  expect(normalizeSwapAssetSelection(REQUEST)).toMatchObject({ from: ESTIMATE.from, to: ESTIMATE.to });
  const result = rememberSwapExecutionQuote('account', REQUEST, ESTIMATE);
  expect(result).toMatchObject({ ourFee: '0', ourFeePercent: 0, networkFee: '0.001' });
  for (const field of ['vtNativeFeeBudget', 'estimateId', 'ourFeeMode']) expect(result).not.toHaveProperty(field);
  expect(prepareSwapBuildRequest('account', makeBuildRequest())).toMatchObject({
    from: ESTIMATE.from, to: ESTIMATE.to, vtNativeFeeBudget: '0.004',
  });
  expect(getSwapExecutionQuote('account', makeBuildRequest()).destinationToken.chain).toBe('arbitrum');
});

test.each([
  { from: '0x3333333333333333333333333333333333333333' },
  { to: mockSource.tokenAddress },
  { toAddress: OWNER },
  { fromAddress: RECIPIENT },
  { fromAmount: '101' },
  { toMinAmount: '97' },
  { networkFee: '0.002' },
  { ourFee: '1' },
  { slippage: 2 },
  { swapMode: 'exact_out' as const },
])('rejects changed confirmation fields: %p', (change) => {
  rememberSwapExecutionQuote('account', REQUEST, ESTIMATE);
  expect(() => prepareSwapBuildRequest('account', { ...makeBuildRequest(), ...change })).toThrow();
});

test('a confirmation is account-bound and expires without a new estimate', () => {
  expect(() => prepareSwapBuildRequest('account', makeBuildRequest())).toThrow('fresh estimate');
  rememberSwapExecutionQuote('account', REQUEST, ESTIMATE);
  expect(() => prepareSwapBuildRequest('other-account', makeBuildRequest())).toThrow('fresh estimate');
  jest.advanceTimersByTime(5 * 60 * 1000);
  expect(() => prepareSwapBuildRequest('account', makeBuildRequest())).toThrow('fresh estimate');
});

test('identical displayed quotes never increase either confirmed signing ceiling', () => {
  rememberSwapExecutionQuote('account', REQUEST, { ...ESTIMATE, vtNativeFeeBudget: '0.003' });
  rememberSwapExecutionQuote('account', REQUEST, ESTIMATE);
  expect(getSwapExecutionQuote('account', makeBuildRequest()).nativeFeeBudget).toBe('0.003');
});

test('VT rejects an unresolved address instead of inferring its network from the backend plan', () => {
  expect(() => rememberSwapExecutionQuote('account', {
    ...REQUEST, from: '0x6985884c4392d348587b19cb9eaaf157f13271cd',
  }, ESTIMATE)).toThrow('Ambiguous execution quote assets');
});

test('same-chain and other providers keep the existing contract', () => {
  const request = { from: 'TON', to: 'USDT', fromAmount: '1' };
  expect(normalizeSwapAssetSelection(request)).toEqual(request);
  expect(prepareSwapBuildRequest('account', { ...request, fromAddress: 'owner' })).toEqual({
    ...request, fromAddress: 'owner',
  });
  expect(rememberSwapExecutionQuote('account', REQUEST, { ...ESTIMATE, dexRouterLabel: 'lifi' }))
    .not.toHaveProperty('estimateId');
  expect(normalizeSwapAssetSelection({ ...REQUEST, to: REQUEST.from })).toEqual({ ...REQUEST, to: REQUEST.from });
});

function makeBuildRequest(): ApiSwapBuildTransactionRequest {
  return {
    ...REQUEST, swapVersion: undefined, fromAmount: '100', fromAddress: OWNER,
    dexRouterLabel: 'layerzero', toMinAmount: '98', ourFee: '0', networkFee: '0.001', swapMode: 'exact_in',
  };
}
