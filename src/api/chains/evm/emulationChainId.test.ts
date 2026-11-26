import { encodeRlp, Transaction } from 'ethers';

import { fetchJson } from '../../../util/fetch';
import { getEvmProvider } from './util/client';
import { parseTransactionForPreview } from './emulation';

jest.mock('../../../util/fetch', () => ({ fetchJson: jest.fn() }));
jest.mock('./util/metadata', () => ({ updateTokensMetadataByAddress: jest.fn() }));
jest.mock('./util/client', () => ({ getEvmProvider: jest.fn() }));
jest.mock('../../common/helpers', () => ({ updateActivityMetadata: (activity: unknown) => activity }));

const WALLET = '0x11a43b91414b2c7083888d8f4e963988ddee12a3';
const RECIPIENT = '0x2222222222222222222222222222222222222222';
const AMOUNT = 10n ** 18n;

function plainTransfer(chainId: number): string {
  return Transaction.from({
    chainId, to: RECIPIENT, value: AMOUNT, nonce: 5, gasLimit: 21_000n, gasPrice: 1_000_000_000n,
  }).unsignedSerialized;
}

function contractCall(chainId: number): string {
  return Transaction.from({
    chainId, to: RECIPIENT, value: AMOUNT, data: '0x12345678', gasLimit: 160_000n, gasPrice: 1_000_000_000n,
  }).unsignedSerialized;
}

beforeEach(() => {
  jest.clearAllMocks();
  // The session chain would simulate any of these transactions as a native transfer
  jest.mocked(fetchJson).mockResolvedValue({
    result: {
      changes: [{
        assetType: 'NATIVE', changeType: 'TRANSFER', from: WALLET, to: RECIPIENT, rawAmount: String(AMOUNT),
      }],
      gasUsed: '0x5208',
    },
  });
});

describe('EVM preview of a transaction a dApp serialized', () => {
  it.each([
    ['a plain transfer with no chain id', encodeRlp([
      '0x05', '0x3b9aca00', '0x5208', RECIPIENT, '0x0de0b6b3a7640000', '0x',
    ])],
    ['a plain transfer for Ethereum', plainTransfer(1)],
    ['a contract call for Ethereum', contractCall(1)],
    ['a contract call for Polygon testnet', contractCall(80002)],
    ['a contract call for a chain the wallet does not know', contractCall(777_777)],
  ])('shows %s as dangerous on Polygon mainnet and simulates nothing', async (_name, rawTx) => {
    const { transfers, emulation } = await parseTransactionForPreview('polygon', rawTx, WALLET, 'mainnet');

    expect(transfers).toEqual([expect.objectContaining({ chain: 'polygon', isDangerous: true, rawPayload: rawTx })]);
    expect(emulation).toBeUndefined();
    expect(fetchJson).not.toHaveBeenCalled();
    expect(getEvmProvider).not.toHaveBeenCalled();
  });

  it('previews a plain transfer for the session chain', async () => {
    const { transfers, emulation } = await parseTransactionForPreview('polygon', plainTransfer(137), WALLET, 'mainnet');

    expect(transfers).toEqual([expect.objectContaining({ isDangerous: false })]);
    expect(emulation?.activities).toEqual([expect.objectContaining({ amount: -AMOUNT })]);
  });
});
