import { Address, Cell } from '@ton/core';

import type { UnifiedSignDataPayload } from '../../dappProtocols';
import type { ApiAccountWithChain } from '../../types';
import type { Signer } from './util/signer';

import { getSigner } from './util/signer';
import { fetchStoredChainAccount } from '../../common/accounts';
import { signDappData } from './dapp';

jest.mock('./util/signer', () => ({ getSigner: jest.fn() }));
jest.mock('../../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../../common/mfa', () => ({ createMfaRequest: jest.fn() }));
jest.mock('../../common/tokens', () => ({ getTokenBySlug: jest.fn() }));
jest.mock('./transfer', () => ({ signTransfers: jest.fn() }));

const ACCOUNT_ID = '0-mainnet';
const ENCLAVE_TOKEN = 'test-enclave-token';
const RAW_ADDRESS = `0:${'abcdef01'.repeat(8)}`;
const TIMESTAMP = 1703980800;
const DAPP_URL = 'https://app.example:8443/sign';
const SIGNATURE = Buffer.alloc(64, 7);
const mockSignData = jest.fn<ReturnType<Signer['signData']>, Parameters<Signer['signData']>>();

const payloads: UnifiedSignDataPayload[] = [
  { type: 'text', text: 'Sign in to the dApp' },
  { type: 'binary', bytes: Buffer.from('test payload').toString('base64') },
  { type: 'cell', schema: 'empty$_ = Empty;', cell: Cell.EMPTY.toBoc().toString('base64') },
];
const addresses = [
  { format: 'bounceable', address: Address.parseRaw(RAW_ADDRESS).toString({ bounceable: true }) },
  { format: 'non-bounceable', address: Address.parseRaw(RAW_ADDRESS).toString({ bounceable: false }) },
  { format: 'raw', address: RAW_ADDRESS },
];

function mockAccount(address: string) {
  const account: ApiAccountWithChain<'ton'> = Object.freeze({
    type: 'ton',
    byChain: Object.freeze({
      ton: Object.freeze({ address, version: 'W5', publicKey: '11'.repeat(32), index: 0 }),
    }),
  });
  jest.mocked(fetchStoredChainAccount).mockResolvedValue(account);
  return account;
}

describe('signDappData TON Connect response', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSignData.mockReset().mockResolvedValue(SIGNATURE);
    jest.mocked(getSigner).mockReturnValue({ signData: mockSignData } as unknown as Signer);
    jest.spyOn(Date, 'now').mockReturnValue(TIMESTAMP * 1000 + 999);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it.each(payloads.map((payload, index) => ({ ...addresses[index], payload, type: payload.type })))(
    'returns a canonical raw address for $type with a $format stored address',
    async ({ address, payload }) => {
      const account = mockAccount(address);
      Object.freeze(payload);

      const result = await signDappData(ACCOUNT_ID, DAPP_URL, payload, ENCLAVE_TOKEN);

      expect(result).toEqual({
        chain: 'ton',
        result: {
          signature: SIGNATURE.toString('base64'),
          address: RAW_ADDRESS,
          timestamp: TIMESTAMP,
          domain: 'app.example:8443',
          payload,
        },
      });
      expect(fetchStoredChainAccount).toHaveBeenCalledWith(ACCOUNT_ID, 'ton');
      expect(getSigner).toHaveBeenCalledWith(ACCOUNT_ID, account, ENCLAVE_TOKEN);
      expect(mockSignData).toHaveBeenCalledTimes(1);
      expect(mockSignData).toHaveBeenCalledWith(TIMESTAMP, 'app.example:8443', payload);
    },
  );
});
