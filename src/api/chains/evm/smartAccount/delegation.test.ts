import { getEvmDelegationAddress } from '../approvals';
import { ALCHEMY_7702_DELEGATEE_ADDRESSES } from './constants';
import {
  getForeignEvmDelegationAddress,
  isAlchemy7702Delegated,
  withForeignDelegationResetCall,
} from './delegation';

jest.mock('../approvals', () => ({
  getEvmDelegationAddress: jest.fn(),
}));

const mockedGetEvmDelegationAddress = jest.mocked(getEvmDelegationAddress);

const CHAIN = 'ethereum' as const;
const NETWORK = 'testnet' as const;
const ADDRESS = '0x1111111111111111111111111111111111111111';
const FOREIGN_DELEGATE = '0x000000009B1D0aF20D8C6d0A44e162d11F9b8f00';
const ALCHEMY_DELEGATE = [...ALCHEMY_7702_DELEGATEE_ADDRESSES][0];

describe('isAlchemy7702Delegated', () => {
  it('returns true when the EOA is delegated to an Alchemy SemiModularAccount7702', async () => {
    mockedGetEvmDelegationAddress.mockResolvedValue(ALCHEMY_DELEGATE);

    await expect(isAlchemy7702Delegated(CHAIN, NETWORK, ADDRESS)).resolves.toBe(true);
  });

  it('returns false when the EOA has no delegation', async () => {
    mockedGetEvmDelegationAddress.mockResolvedValue(undefined);

    await expect(isAlchemy7702Delegated(CHAIN, NETWORK, ADDRESS)).resolves.toBe(false);
  });
});

describe('getForeignEvmDelegationAddress', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns undefined when the EOA has no delegation', async () => {
    mockedGetEvmDelegationAddress.mockResolvedValue(undefined);

    await expect(getForeignEvmDelegationAddress(CHAIN, NETWORK, ADDRESS)).resolves.toBeUndefined();
  });

  it('returns undefined when the EOA is delegated to Alchemy SemiModularAccount7702', async () => {
    mockedGetEvmDelegationAddress.mockResolvedValue(ALCHEMY_DELEGATE);

    await expect(getForeignEvmDelegationAddress(CHAIN, NETWORK, ADDRESS)).resolves.toBeUndefined();
  });

  it('returns the foreign delegate when delegation is not Alchemy SemiModularAccount7702', async () => {
    mockedGetEvmDelegationAddress.mockResolvedValue(FOREIGN_DELEGATE);

    await expect(getForeignEvmDelegationAddress(CHAIN, NETWORK, ADDRESS)).resolves.toBe(FOREIGN_DELEGATE);
  });
});

describe('withForeignDelegationResetCall', () => {
  const SWAP_CALL = {
    to: '0xRouter',
    value: 0n,
    data: '0xswap',
  };

  it('prepends an empty self-call when a foreign delegate is active', () => {
    expect(withForeignDelegationResetCall(ADDRESS, [SWAP_CALL], FOREIGN_DELEGATE)).toEqual([
      {
        to: ADDRESS,
        value: 0n,
        data: '0x',
      },
      SWAP_CALL,
    ]);
  });

  it('leaves calls unchanged when delegation is supported or absent', () => {
    expect(withForeignDelegationResetCall(ADDRESS, [SWAP_CALL])).toEqual([SWAP_CALL]);
    expect(withForeignDelegationResetCall(ADDRESS, [SWAP_CALL], undefined)).toEqual([SWAP_CALL]);
  });
});
