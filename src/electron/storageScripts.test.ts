import { Script } from 'vm';

import { ACTIVE_TAB_STORAGE_KEY } from '../config';
import { buildRestoreLocalStorageScript, getRestorableLocalStorageEntries } from './storageScripts';

function runRestoreLocalStorageScript(script: string) {
  const values = new Map<string, string>();
  const localStorage = {
    setItem: jest.fn((key: string, value: string) => {
      values.set(key, value);
    }),
  };
  const sandbox = { localStorage } as { localStorage: typeof localStorage; __pwned?: boolean };

  new Script(script).runInNewContext(sandbox);

  return { localStorage, sandbox, values };
}

describe('storageScripts', () => {
  it('restores poisoned keys as data', () => {
    const key = 'poc\'); globalThis.__pwned = true; (\'';
    const script = buildRestoreLocalStorageScript([[key, '1']]);
    const { sandbox, values } = runRestoreLocalStorageScript(script);

    expect(sandbox.__pwned).toBeUndefined();
    expect(values.get(key)).toBe('1');
  });

  it('restores poisoned values as data', () => {
    const value = '1)); globalThis.__pwned = true; JSON.stringify((2';
    const script = buildRestoreLocalStorageScript([['key', value]]);
    const { sandbox, values } = runRestoreLocalStorageScript(script);

    expect(sandbox.__pwned).toBeUndefined();
    expect(values.get('key')).toBe(value);
  });

  it('round-trips localStorage strings exactly', () => {
    const entries = [
      ['plain', 'value'],
      ['json', '{"theme":"dark","count":1}'],
      ['quoted', '"value"'],
      ['slashes', String.raw`C:\Wallet\profile`],
      ['unicode', 'Привет'],
    ] as const;

    const { values } = runRestoreLocalStorageScript(buildRestoreLocalStorageScript([...entries]));

    entries.forEach(([key, value]) => {
      expect(values.get(key)).toBe(value);
    });
  });

  it('excludes the active tab marker from restorable entries', () => {
    const entries = getRestorableLocalStorageEntries({
      [ACTIVE_TAB_STORAGE_KEY]: 'active-tab',
      settings: '{"theme":"dark"}',
    });

    expect(entries).toEqual([['settings', '{"theme":"dark"}']]);
  });
});
