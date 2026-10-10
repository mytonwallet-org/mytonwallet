const ENV_KEYS = [
  'AGENT_OVERRIDE',
  'AGENT_V2_QUOTA_STATUS_ENABLED',
] as const;
type EnvKey = (typeof ENV_KEYS)[number];

const savedValues = Object.fromEntries(
  ENV_KEYS.map((key) => [key, process.env[key]]),
) as Record<EnvKey, string | undefined>;

afterAll(() => {
  ENV_KEYS.forEach((key) => setEnvValue(key, savedValues[key]));
});

describe('Agent V2 rollout config', () => {
  describe('AGENT_OVERRIDE', () => {
    it.each([
      ['unset', undefined, 'no_override'],
      ['runtime', 'no_override', 'no_override'],
      ['V1', 'v1', 'v1'],
      ['V2', 'v2', 'v2'],
    ] as const)('resolves the override when %s', async (_name, value, expected) => {
      expect(await readConfigValue('AGENT_OVERRIDE', value)).toBe(expected);
    });

    it('rejects unsupported values', async () => {
      await expect(readConfigValue('AGENT_OVERRIDE', 'future')).rejects.toThrow(
        'Unsupported AGENT_OVERRIDE value: future',
      );
    });
  });

  describe('AGENT_V2_QUOTA_STATUS_ENABLED', () => {
    it.each([
      ['unset', undefined, false],
      ['disabled', '0', false],
      ['enabled', '1', true],
      ['invalid', 'true', false],
    ] as const)('resolves the flag when %s', async (_name, value, expected) => {
      expect(await readConfigValue('AGENT_V2_QUOTA_STATUS_ENABLED', value)).toBe(expected);
    });
  });
});

async function readConfigValue(envKey: EnvKey, value: string | undefined) {
  const previousValue = process.env[envKey];
  setEnvValue(envKey, value);

  let result: boolean | string | undefined;
  try {
    await jest.isolateModulesAsync(async () => {
      const config = await import('./config');
      result = config[envKey];
    });
    return result;
  } finally {
    setEnvValue(envKey, previousValue);
  }
}

function setEnvValue(envKey: EnvKey, value: string | undefined) {
  if (value === undefined) {
    delete process.env[envKey];
  } else {
    process.env[envKey] = value;
  }
}
