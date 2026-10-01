import { Address, beginCell } from '@ton/core';

import { STON_PTON_ADDRESS } from '../../../config';
import { JettonOpCode, OpCode } from './constants';
import { isTokenBalanceInsufficient } from './transfer';

const mockResolveTokenWallet = jest.fn();
const mockGetTokenBalanceWithMintless = jest.fn();

jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  resolveTokenWallet: (...args: unknown[]) => mockResolveTokenWallet(...args),
}));

jest.mock('./tokens', () => ({
  ...jest.requireActual('./tokens'),
  getTokenBalanceWithMintless: (...args: unknown[]) => mockGetTokenBalanceWithMintless(...args),
}));

const NETWORK = 'mainnet';
const WALLET_ADDRESS = `0:${'1'.repeat(64)}`;
const TOKEN_WALLET_ADDRESS = `0:${'2'.repeat(64)}`;
const TOKEN_ADDRESS = `0:${'3'.repeat(64)}`;
const RECIPIENT_ADDRESS = `0:${'4'.repeat(64)}`;
const TOKEN_AMOUNT = 123n;

describe('isTokenBalanceInsufficient', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('treats a jetton transfer from a wallet that is not deployed as insufficient', async () => {
    mockResolveTokenWallet.mockRejectedValue(new Error('Token wallet is not deployed'));

    const result = await checkTransfer(buildJettonTransferPayload());

    expect(result.hasInsufficientTokenBalance).toBe(true);
  });

  it('treats a jetton transfer from a wallet of another owner as insufficient', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: RECIPIENT_ADDRESS });

    const result = await checkTransfer(buildJettonTransferPayload());

    expect(result.hasInsufficientTokenBalance).toBe(true);
  });

  it.each([
    [TOKEN_AMOUNT, false],
    [TOKEN_AMOUNT - 1n, true],
  ])('compares the transfer with the balance %s of a verified wallet', async (balance, isInsufficient) => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: TOKEN_ADDRESS, ownerAddress: WALLET_ADDRESS });
    mockGetTokenBalanceWithMintless.mockResolvedValue(balance);

    const result = await checkTransfer(buildJettonTransferPayload());

    expect(result.hasInsufficientTokenBalance).toBe(isInsufficient);
  });

  it('skips the balance of a STON.fi v1 proxy TON deposit', async () => {
    mockResolveTokenWallet.mockResolvedValue({ tokenAddress: STON_PTON_ADDRESS, ownerAddress: RECIPIENT_ADDRESS });

    const result = await checkTransfer(buildJettonTransferPayload());

    expect(result.hasInsufficientTokenBalance).toBe(false);
    expect(mockGetTokenBalanceWithMintless).not.toHaveBeenCalled();
  });

  it('ignores a payload that is not a jetton transfer', async () => {
    const comment = beginCell().storeUint(OpCode.Comment, 32).storeStringTail('Hello').endCell();

    const result = await checkTransfer(comment);

    expect(result.hasInsufficientTokenBalance).toBe(false);
    expect(mockResolveTokenWallet).not.toHaveBeenCalled();
  });
});

function checkTransfer(payload: ReturnType<typeof buildJettonTransferPayload>) {
  return isTokenBalanceInsufficient(NETWORK, WALLET_ADDRESS, [{
    toAddress: TOKEN_WALLET_ADDRESS,
    amount: 1n,
    payload,
  }]);
}

function buildJettonTransferPayload() {
  return beginCell()
    .storeUint(JettonOpCode.Transfer, 32)
    .storeUint(1n, 64)
    .storeCoins(TOKEN_AMOUNT)
    .storeAddress(Address.parse(RECIPIENT_ADDRESS))
    .storeAddress(Address.parse(WALLET_ADDRESS))
    .storeMaybeRef(undefined)
    .storeCoins(0n)
    .storeBit(0)
    .endCell();
}
