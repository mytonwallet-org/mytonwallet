beforeEach(() => {
  jest.resetModules();
});

describe('Agent V2 API environment', () => {
  it.each([
    ['no_override', false],
    ['v1', false],
    ['v2', true],
  ] as const)('uses the %s build override', (agentOverride, isAgentV2Enabled) => {
    const { setEnvironment } = loadEnvironment(agentOverride);

    expect(setEnvironment({}).isAgentV2Enabled).toBe(isAgentV2Enabled);
  });

  it.each(['no_override', 'v1', 'v2'] as const)('prefers the explicit %s runtime override', (agentOverride) => {
    const { setEnvironment } = loadEnvironment(agentOverride === 'v2' ? 'v1' : 'v2');

    const environment = setEnvironment({ agentOverride });
    expect(environment.agentOverride).toBe(agentOverride);
    expect(environment.isAgentV2Enabled).toBe(agentOverride === 'v2');
  });

  it('enables Agent V2 on Android despite V1 overrides', () => {
    const { setEnvironment } = loadEnvironment('v1');

    expect(setEnvironment({ agentOverride: 'v1', isAndroidApp: true }).isAgentV2Enabled).toBe(true);
  });
});

function loadEnvironment(agentOverride: 'no_override' | 'v1' | 'v2') {
  jest.doMock('../config', () => ({
    AGENT_OVERRIDE: agentOverride,
    ELECTRON_TONCENTER_MAINNET_KEY: '',
    ELECTRON_TONCENTER_TESTNET_KEY: '',
    IS_AIR_APP: false,
    IS_EXTENSION: false,
    TONCENTER_MAINNET_KEY: '',
    TONCENTER_TESTNET_KEY: '',
  }));

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  return require('./environment') as typeof import('./environment');
}
