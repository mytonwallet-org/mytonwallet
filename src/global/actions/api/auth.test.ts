import './auth';

import type { GlobalState } from '../../types';
import { AppState, AuthState } from '../../types';

import { enclave } from '../../../enclave';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../api', () => ({
  callApi: jest.fn(() => Promise.resolve(true)),
}));

jest.mock('../../../enclave', () => ({
  enclave: {
    setupAuth: jest.fn(),
    authorize: jest.fn(),
    isAuthProvisioned: jest.fn(() => Promise.resolve(false)),
    hasProvisionedAuth: jest.fn(() => Promise.resolve(false)),
    hasStoredSecrets: jest.fn(() => Promise.resolve(true)),
    reset: jest.fn(),
    importSecret: jest.fn(),
    duplicateSecret: jest.fn(),
    migrateAuth: jest.fn(),
  },
  legacyAuth: {
    migrateFromLegacy: jest.fn(),
    migrateFromLegacyBiometric: jest.fn(),
    getPasswordFromLegacyBiometrics: jest.fn(),
  },
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => unknown;

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

const ACCOUNT_ID = '0-ton-mainnet';
const PASSWORD = '123456';
const MNEMONIC = 'plastic burst injury easily panther auto snack call volume humor ritual thrive'.split(' ');

function makeGlobal(overrides: Partial<GlobalState>): GlobalState {
  return {
    auth: {},
    settings: { isTestnet: false },
    accounts: {
      byId: {
        [ACCOUNT_ID]: { title: 'Wallet', type: 'mnemonic', byChain: { ton: { address: 'ton-address' } } },
      },
    },
    ...overrides,
  } as unknown as GlobalState;
}

describe('add-account routing', () => {
  let store: GlobalState;

  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
    (getGlobal as jest.Mock).mockImplementation(() => store);
    (setGlobal as jest.Mock).mockImplementation((next: GlobalState) => {
      store = next;
    });
  });

  async function run(name: string, global: GlobalState, actions: AnyLiteral = {}, payload?: AnyLiteral) {
    store = global;
    await getHandler(name)(store, actions, payload);
    return store;
  }

  // A password entered in the "Add Wallet" modal yields a usage-counted session, which global state
  // cannot recognise as valid. The token it produced is what proves the flow is already authorized.
  it('proceeds to mnemonic entry when the account selector already authorized', async () => {
    const result = await run('startImportingWallet', makeGlobal({
      authTypes: ['passcode'],
      enclaveSession: { token: 'passcode:aa' },
    }), {}, { enclaveToken: 'passcode:aa' });

    expect(result.auth.state).toBe(AuthState.importWallet);
  });

  it('asks for the password when there is no session at all', async () => {
    const result = await run('startImportingWallet', makeGlobal({ authTypes: ['passcode'] }));

    expect(result.auth.state).toBe(AuthState.importWalletCheckPassword);
  });

  // Accounts exist but `authTypes` is empty: the user still lives on legacy auth and has a password.
  // Offering to create a new one strands the legacy secrets outside the Enclave.
  it('asks a not-yet-migrated user for the existing password instead of creating a new one', async () => {
    const result = await run('startImportingWallet', makeGlobal({}));

    expect(result.auth.state).toBe(AuthState.importWalletCheckPassword);
  });

  it('shows the password screen inside the auth flow when creating a wallet', async () => {
    const result = await run('startCreatingWallet', makeGlobal({ authTypes: ['passcode'] }));

    expect(result.auth.state).toBe(AuthState.checkPassword);
    expect(result.appState).toBe(AppState.Auth);
  });

  // The creation path fails more quietly than the import one, since the screen it wants is never
  // mounted for an existing wallet, so an unanswered request for a password shows up as a spinner
  // that never resolves rather than as a screen the user can recognise.
  it('starts creating the wallet when the account selector already authorized', async () => {
    const actions = { createAccount: jest.fn() };
    const result = await run('startCreatingWallet', makeGlobal({
      authTypes: ['passcode'],
      enclaveSession: { token: 'passcode:aa' },
    }), actions, { enclaveToken: 'passcode:aa' });

    expect(result.auth.state).toBe(AuthState.safetyRules);
    expect(actions.createAccount).toHaveBeenCalled();
  });

  it('does not offer to create a password to a not-yet-migrated user after the mnemonic is entered', async () => {
    const actions = { confirmDisclaimer: jest.fn() };
    const result = await run('afterImportMnemonic', makeGlobal({}), actions, { mnemonic: MNEMONIC });

    expect(result.auth.state).toBeUndefined();
    expect(actions.confirmDisclaimer).toHaveBeenCalled();
  });
});

describe('auth setup over existing storage', () => {
  let store: GlobalState;

  /** Reproduces what the storage answers once the auth of the given type is provisioned, or none is. */
  function stubStorage({ authType, hasSecrets }: { authType?: 'passcode' | 'biometric'; hasSecrets: boolean }) {
    (enclave.hasProvisionedAuth as jest.Mock).mockResolvedValue(Boolean(authType));
    (enclave.isAuthProvisioned as jest.Mock).mockImplementation((type: string) => Promise.resolve(type === authType));
    (enclave.hasStoredSecrets as jest.Mock).mockResolvedValue(hasSecrets);
  }

  beforeEach(() => {
    (setGlobal as jest.Mock).mockClear();
    (getGlobal as jest.Mock).mockImplementation(() => store);
    (setGlobal as jest.Mock).mockImplementation((next: GlobalState) => {
      store = next;
    });
    (enclave.setupAuth as jest.Mock).mockReset();
    (enclave.authorize as jest.Mock).mockReset();
    (enclave.isAuthProvisioned as jest.Mock).mockReset();
    (enclave.hasProvisionedAuth as jest.Mock).mockReset();
    (enclave.hasStoredSecrets as jest.Mock).mockReset();
    // Emptying the storage is what makes the setup that follows the reset possible, so the stubs have to
    // stop reporting the auth that was just destroyed
    (enclave.reset as jest.Mock).mockReset().mockImplementation(() => {
      stubStorage({ hasSecrets: false });
      return Promise.resolve();
    });
    stubStorage({ hasSecrets: false });
  });

  async function createPassword(actions: AnyLiteral = { createAccount: jest.fn() }) {
    store = makeGlobal({});
    await getHandler('createPassword')(store, actions, { password: PASSWORD });
    return store;
  }

  async function setupBiometricAuth(actions: AnyLiteral = { createAccount: jest.fn() }) {
    store = makeGlobal({});
    await getHandler('setupBiometricAuth')(store, actions);
    return store;
  }

  it('sets the auth up when the storage holds none', async () => {
    (enclave.setupAuth as jest.Mock).mockResolvedValue({ token: 'passcode:new' });

    const result = await createPassword();

    expect(enclave.setupAuth).toHaveBeenCalledWith('passcode', PASSWORD);
    expect(enclave.authorize).not.toHaveBeenCalled();
    expect(result.enclaveSession).toEqual({ token: 'passcode:new' });
  });

  // Setting an auth up a second time mints a fresh master key and seals every stored secret under a key
  // nothing can reproduce, so a storage that is already configured has to be authorized against
  it('authorizes against an auth the storage already holds', async () => {
    stubStorage({ authType: 'passcode', hasSecrets: true });
    (enclave.authorize as jest.Mock).mockResolvedValue({ token: 'passcode:resumed' });
    const actions = { createAccount: jest.fn() };

    const result = await createPassword(actions);

    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(enclave.authorize).toHaveBeenCalledWith('passcode', false, PASSWORD);
    expect(result.enclaveSession).toEqual({ token: 'passcode:resumed' });
    expect(actions.createAccount).toHaveBeenCalled();
  });

  it('says the password is wrong when it does not open the existing auth', async () => {
    stubStorage({ authType: 'passcode', hasSecrets: true });
    (enclave.authorize as jest.Mock).mockResolvedValue(undefined);

    const result = await createPassword();

    expect(result.auth.error).toBe('Wrong password, please try again.');
    expect(result.auth.isLoading).toBe(false);
  });

  // An auth left behind by a setup that never imported anything guards nothing, and asking for the
  // password that opens it would ask the user to guess something with no wallet behind it
  it('clears an auth that guards no secrets and sets one up anew', async () => {
    stubStorage({ authType: 'passcode', hasSecrets: false });
    (enclave.setupAuth as jest.Mock).mockResolvedValue({ token: 'passcode:fresh' });

    const result = await createPassword();

    expect(enclave.reset).toHaveBeenCalled();
    expect(enclave.setupAuth).toHaveBeenCalledWith('passcode', PASSWORD);
    expect(enclave.authorize).not.toHaveBeenCalled();
    expect(result.enclaveSession).toEqual({ token: 'passcode:fresh' });
  });

  it('keeps an auth that still guards secrets', async () => {
    stubStorage({ authType: 'passcode', hasSecrets: true });
    (enclave.authorize as jest.Mock).mockResolvedValue({ token: 'passcode:resumed' });

    await createPassword();

    expect(enclave.reset).not.toHaveBeenCalled();
  });

  // The master key is one per storage, so a leftover passcode auth is what `setupAuth('biometric')`
  // refuses over, even though no biometric auth was ever provisioned
  it('clears a leftover auth of another type before setting up biometrics', async () => {
    stubStorage({ authType: 'passcode', hasSecrets: false });
    (enclave.setupAuth as jest.Mock).mockResolvedValue({ token: 'biometric:fresh' });

    const result = await setupBiometricAuth();

    expect(enclave.reset).toHaveBeenCalled();
    expect(enclave.setupAuth).toHaveBeenCalledWith('biometric');
    expect(result.enclaveSession).toEqual({ token: 'biometric:fresh' });
  });

  it('authorizes against a biometric auth the storage already holds', async () => {
    stubStorage({ authType: 'biometric', hasSecrets: true });
    (enclave.authorize as jest.Mock).mockResolvedValue({ token: 'biometric:resumed' });

    const result = await setupBiometricAuth();

    expect(enclave.reset).not.toHaveBeenCalled();
    expect(enclave.setupAuth).not.toHaveBeenCalled();
    expect(result.enclaveSession).toEqual({ token: 'biometric:resumed' });
  });

  // Nothing was being set up on this path, so naming the setup would send the user looking in the
  // wrong place for what is a declined or failed confirmation
  it('reports a refused confirmation rather than a failed setup', async () => {
    stubStorage({ authType: 'biometric', hasSecrets: true });
    (enclave.authorize as jest.Mock).mockResolvedValue(undefined);

    const result = await setupBiometricAuth();

    expect(result.auth.error).toBe('Biometric confirmation failed.');
    expect(result.auth.isLoading).toBe(false);
  });
});
