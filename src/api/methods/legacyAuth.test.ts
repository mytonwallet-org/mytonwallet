import { cleanupLegacyAuthAfterMigration } from './legacyAuth';

jest.mock('../../util/windowProvider/connector', () => ({
  callWindow: jest.fn(),
}));

const mockStorage = {
  getItem: jest.fn(),
  setItem: jest.fn(),
};

jest.mock('../storages', () => ({
  get storage() {
    return mockStorage;
  },
}));

function createAccounts() {
  return {
    '0-mainnet': { mnemonicEncrypted: 'blob-0', byChain: {} },
    '1-mainnet': { mnemonicEncrypted: 'blob-1', byChain: {} },
    '2-mainnet': { mnemonicEncrypted: 'blob-2', byChain: {} },
  };
}

describe('cleanupLegacyAuthAfterMigration', () => {
  beforeEach(() => {
    mockStorage.getItem.mockReset();
    mockStorage.setItem.mockReset();
  });

  it('drops every mnemonic the enclave has taken over', async () => {
    mockStorage.getItem.mockResolvedValue(createAccounts());

    await cleanupLegacyAuthAfterMigration(['0-mainnet', '1-mainnet', '2-mainnet']);

    const [, written] = mockStorage.setItem.mock.calls[0];
    expect(Object.keys(written)).toEqual(['0-mainnet', '1-mainnet', '2-mainnet']);
    expect(Object.values(written).every((account: any) => !account.mnemonicEncrypted)).toBe(true);
  });

  // The blob of an account the enclave holds no secret for is the only copy of that wallet left
  it('leaves the mnemonic of a skipped account alone', async () => {
    mockStorage.getItem.mockResolvedValue(createAccounts());

    await cleanupLegacyAuthAfterMigration(['0-mainnet', '2-mainnet']);

    const [, written] = mockStorage.setItem.mock.calls[0];
    expect(written['1-mainnet'].mnemonicEncrypted).toBe('blob-1');
    expect(written['0-mainnet'].mnemonicEncrypted).toBeUndefined();
    expect(written['2-mainnet'].mnemonicEncrypted).toBeUndefined();
  });

  // Android storage hands out the cached object itself, so a failed write must not leave it stripped
  it('leaves the object it was given untouched', async () => {
    const accounts = createAccounts();
    mockStorage.getItem.mockResolvedValue(accounts);

    await cleanupLegacyAuthAfterMigration(['0-mainnet', '1-mainnet', '2-mainnet']);

    expect(accounts['0-mainnet'].mnemonicEncrypted).toBe('blob-0');
  });

  // An empty list is what a caller that lost track of the migration passes, and erasing on it would
  // destroy wallets the enclave never took over
  it('writes nothing when no account is named', async () => {
    mockStorage.getItem.mockResolvedValue(createAccounts());

    await cleanupLegacyAuthAfterMigration([]);

    expect(mockStorage.setItem).not.toHaveBeenCalled();
  });
});
