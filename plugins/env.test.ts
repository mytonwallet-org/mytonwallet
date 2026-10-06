import { describeEnv } from './env';

describe('describeEnv', () => {
  it('names the source of every key, so a default is never mistaken for a decision', () => {
    const lines = describeEnv(
      { AGENT_API_URL: '', APP_ENV: 'production' },
      { AGENT_API_URL: 'https://agent-beta.mytonwallet.org/api' },
    );

    expect(lines).toEqual([
      'Build-time env: 2 keys baked in, 1 supplied by the environment',
      '  [env]     AGENT_API_URL = "https://agent-beta.mytonwallet.org/api"',
      '  [default] APP_ENV = "production"',
    ]);
  });

  // The failure this report exists for: an unset repository variable reaches the build as an empty
  // string, which `defineEnv` keeps, so the bundle silently falls through to the production default.
  it('reports a key the environment set to an empty string as coming from the environment', () => {
    expect(describeEnv({ AGENT_API_URL: '' }, { AGENT_API_URL: '' }))
      .toContain('  [env]     AGENT_API_URL = ""');
  });

  it('states that a credential was supplied without printing it', () => {
    const lines = describeEnv({ TONCENTER_MAINNET_KEY: '' }, { TONCENTER_MAINNET_KEY: 'c0ffee'.repeat(6) });

    expect(lines).toContain('  [env]     TONCENTER_MAINNET_KEY = <supplied, 36 chars>');
    expect(lines.join('\n')).not.toContain('c0ffee');
  });

  it('keeps an empty credential readable, because an absent secret is what a build log has to show', () => {
    expect(describeEnv({ SOLANA_MAINNET_API_KEY: '' }, {}))
      .toContain('  [default] SOLANA_MAINNET_API_KEY = ""');
  });

  it('treats a session as a credential, since the web build bakes one in', () => {
    expect(describeEnv({ TEST_SESSION: '' }, { TEST_SESSION: 'abc123' }))
      .toContain('  [env]     TEST_SESSION = <supplied, 6 chars>');
  });

  // The case a rule built on key names cannot see: the credential is in the value, under a name
  // that only says "url".
  it('redacts a key carried inside a URL rather than trusting the key name', () => {
    const lines = describeEnv(
      { EVM_MAINNET_RPC_URL: '' },
      { EVM_MAINNET_RPC_URL: 'https://eth-mainnet.g.alchemy.com/v2/uPb7t2kVsecretkey' },
    );

    expect(lines).toContain('  [env]     EVM_MAINNET_RPC_URL = "https://eth-mainnet.g.alchemy.com/v2/<redacted>"');
    expect(lines.join('\n')).not.toContain('uPb7t2kVsecretkey');
  });

  it('leaves a host that carries no credential exactly as configured', () => {
    expect(describeEnv({ AGENT_API_URL: '' }, { AGENT_API_URL: 'https://agent-beta.mytonwallet.org/api' }))
      .toContain('  [env]     AGENT_API_URL = "https://agent-beta.mytonwallet.org/api"');
  });
});
