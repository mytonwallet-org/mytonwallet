import { mnemonicNew } from '@ton/crypto';

import { generateMnemonic } from './auth';

jest.mock('@ton/crypto', () => ({
  ...jest.requireActual('@ton/crypto'),
  mnemonicNew: jest.fn(),
}));

const mockMnemonicNew = jest.mocked(mnemonicNew);

// The standard zero-entropy BIP39 vector: a valid 24-word phrase, so the real validateBip39Mnemonic accepts it and
// generation must reject it as ambiguous.
const AMBIGUOUS = [...Array(23).fill('abandon'), 'art'];
// Twenty-four times "abandon" fails the BIP39 checksum, so it can only be read as a TON-native phrase.
const TON_ONLY = Array(24).fill('abandon');

describe('ton.generateMnemonic', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('rerolls until the phrase is not also a valid BIP39 mnemonic', async () => {
    mockMnemonicNew
      .mockResolvedValueOnce(AMBIGUOUS)
      .mockResolvedValueOnce(TON_ONLY);

    const result = await generateMnemonic();

    // An ambiguous phrase would import as BIP39 at a different address, so it must never be handed out.
    expect(result).toEqual(TON_ONLY);
    expect(mockMnemonicNew).toHaveBeenCalledTimes(2);
  });

  it('returns the first phrase when it is already TON-native only', async () => {
    mockMnemonicNew.mockResolvedValueOnce(TON_ONLY);

    const result = await generateMnemonic();

    expect(result).toEqual(TON_ONLY);
    expect(mockMnemonicNew).toHaveBeenCalledTimes(1);
  });

  it('gives up instead of spinning forever when the generator only yields ambiguous phrases', async () => {
    mockMnemonicNew.mockResolvedValue(AMBIGUOUS);

    await expect(generateMnemonic()).rejects.toThrow('unambiguous');
  });
});
