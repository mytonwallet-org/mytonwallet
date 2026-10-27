import { fetchStoredWallet, updateStoredWallet } from '../common/accounts';
import { getBackendAuthToken, getStoredBackendAuthToken } from './other';

jest.mock('../common/accounts', () => ({
  fetchStoredAccounts: jest.fn(),
  fetchStoredWallet: jest.fn(),
  updateStoredWallet: jest.fn(),
}));
jest.mock('../chains', () => ({ ton: { fetchPrivateKeyString: jest.fn() } }));
jest.mock('../common/backend', () => ({ callBackendGet: jest.fn() }));
jest.mock('../storages', () => ({ storage: { getItem: jest.fn(), setItem: jest.fn() } }));
jest.mock('../../util/logs', () => ({ getLogs: jest.fn(), logDebugError: jest.fn() }));

const ACCOUNT_ID = '0-ton-mainnet';
const AUTH_TOKEN = 'stored-auth-token';
const PUBLIC_KEY = '672317af8e22b20adcbb2a45fe77f79c31411009e2b1358a84c72e516d2e2f97';

describe('backend auth token', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // The backend's own lookup is a get-method on the address, so an account without deployed code is
  // authorized from the key carried by the token instead.
  it('carries the public key for a wallet that is not deployed', async () => {
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      authToken: AUTH_TOKEN, publicKey: PUBLIC_KEY, isInitialized: false,
    } as any);

    await expect(getBackendAuthToken(ACCOUNT_ID, '')).resolves.toBe(`${AUTH_TOKEN}:${PUBLIC_KEY}`);
    await expect(getStoredBackendAuthToken(ACCOUNT_ID)).resolves.toBe(`${AUTH_TOKEN}:${PUBLIC_KEY}`);
  });

  // The flag latches on the first active state the chain reports and never returns from it, so a
  // wallet whose account stopped being active keeps authorizing through the key.
  it('carries the public key for a wallet marked as deployed', async () => {
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      authToken: AUTH_TOKEN, publicKey: PUBLIC_KEY, isInitialized: true,
    } as any);

    await expect(getBackendAuthToken(ACCOUNT_ID, '')).resolves.toBe(`${AUTH_TOKEN}:${PUBLIC_KEY}`);
    await expect(getStoredBackendAuthToken(ACCOUNT_ID)).resolves.toBe(`${AUTH_TOKEN}:${PUBLIC_KEY}`);
  });

  // An absent key would otherwise be interpolated into the token as the literal `undefined`.
  it('omits the suffix when no public key is stored', async () => {
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      authToken: AUTH_TOKEN, publicKey: undefined, isInitialized: false,
    } as any);

    await expect(getBackendAuthToken(ACCOUNT_ID, '')).resolves.toBe(AUTH_TOKEN);
    await expect(getStoredBackendAuthToken(ACCOUNT_ID)).resolves.toBe(AUTH_TOKEN);
  });

  it('leaves the stored token free of the suffix', async () => {
    jest.mocked(fetchStoredWallet).mockResolvedValue({
      authToken: undefined, publicKey: PUBLIC_KEY, isInitialized: false,
    } as any);
    const chains = jest.requireMock('../chains');
    chains.ton.fetchPrivateKeyString.mockResolvedValue('11'.repeat(64));

    const token = await getBackendAuthToken(ACCOUNT_ID, '');

    expect(token.endsWith(`:${PUBLIC_KEY}`)).toBe(true);
    expect(jest.mocked(updateStoredWallet).mock.calls[0][2]).toEqual({
      authToken: token.slice(0, -`:${PUBLIC_KEY}`.length),
    });
  });
});
