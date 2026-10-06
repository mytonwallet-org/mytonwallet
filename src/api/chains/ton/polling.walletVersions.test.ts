import { shouldPollWalletVersions } from './polling';

describe('wallet versions polling guard', () => {
  it('skips alternate wallet version discovery for Telegram Wallet sources', () => {
    expect(shouldPollWalletVersions({ version: 'telegram' })).toBe(false);
  });

  it('allows alternate wallet version discovery for standard TON wallet sources', () => {
    expect(shouldPollWalletVersions({ version: 'W5' })).toBe(true);
  });
});
