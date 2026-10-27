import { getEvmProvider } from './util/client';
import {
  acceptsRawEcdsaSignature,
  canAccountUsePermit2,
  getEvmAccountCode,
  getPermit2SignatureStrategy,
} from './permit2';

jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));

const CHAIN = 'ethereum' as const;
const NETWORK = 'mainnet' as const;
const ADDRESS = '0x1111111111111111111111111111111111111111';

const getCode = jest.fn();
const call = jest.fn();

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(getEvmProvider).mockReturnValue({ getCode, call } as never);
});

describe('getEvmAccountCode', () => {
  it('normalizes empty provider code to 0x for EOAs', async () => {
    getCode.mockResolvedValue('');

    await expect(getEvmAccountCode(CHAIN, NETWORK, ADDRESS)).resolves.toBe('0x');
  });

  it('returns undefined on RPC failure', async () => {
    getCode.mockRejectedValue(new Error('rpc failed'));

    await expect(getEvmAccountCode(CHAIN, NETWORK, ADDRESS)).resolves.toBeUndefined();
  });
});

describe('acceptsRawEcdsaSignature', () => {
  it('treats any full ERC-1271 return word as raw ECDSA envelope support', async () => {
    call.mockResolvedValue(`0x${'00'.repeat(32)}`);

    await expect(acceptsRawEcdsaSignature(CHAIN, NETWORK, ADDRESS)).resolves.toBe(true);
    expect(call.mock.calls[0][0]).toMatchObject({ to: ADDRESS });
  });

  it('rejects reverts or short ERC-1271 responses', async () => {
    call.mockResolvedValue('0x');
    await expect(acceptsRawEcdsaSignature(CHAIN, NETWORK, ADDRESS)).resolves.toBe(false);

    call.mockRejectedValue(new Error('revert'));
    await expect(acceptsRawEcdsaSignature(CHAIN, NETWORK, ADDRESS)).resolves.toBe(false);
  });
});

describe('canAccountUsePermit2', () => {
  it('allows plain EOAs', async () => {
    getCode.mockResolvedValue('0x');

    await expect(canAccountUsePermit2(CHAIN, NETWORK, ADDRESS)).resolves.toBe(true);
    expect(call).not.toHaveBeenCalled();
  });

  it('checks ERC-1271 for code-bearing accounts', async () => {
    getCode.mockResolvedValue('0xef01001111111111111111111111111111111111111111');
    call.mockResolvedValue(`0x${'00'.repeat(32)}`);

    await expect(canAccountUsePermit2(CHAIN, NETWORK, ADDRESS)).resolves.toBe(true);
    await expect(getPermit2SignatureStrategy(CHAIN, NETWORK, ADDRESS)).resolves.toBe('raw');
  });

  it('rejects code-bearing accounts that do not accept raw ECDSA signatures', async () => {
    getCode.mockResolvedValue('0xef01001111111111111111111111111111111111111111');
    call.mockRejectedValue(new Error('revert'));

    await expect(canAccountUsePermit2(CHAIN, NETWORK, ADDRESS)).resolves.toBe(false);
  });

  it('rejects Permit2 when account code cannot be read', async () => {
    getCode.mockRejectedValue(new Error('rpc failed'));

    await expect(canAccountUsePermit2(CHAIN, NETWORK, ADDRESS)).resolves.toBe(false);
  });
});
