import { ContractType } from '../constants';
import { findKnownContract } from './knownContracts';
import { walletClassMap } from './tonCore';

// The trampoline deployed on every Telegram wallet account. The wallet logic itself is not here: it lives in the
// blockchain config under key -123, so this hash is the only thing on the account that identifies the wallet.
const TELEGRAM_CODE_HASH = '9149ae51c1e4689710cebf7830297b16acfbadb363a920a537893e7ffeeca768';

describe('findKnownContract', () => {
  it('knows the Telegram wallet by the hash of its code cell', () => {
    const contract = findKnownContract(TELEGRAM_CODE_HASH);

    expect(contract?.name).toBe('telegram');
    expect(contract?.type).toBe(ContractType.Wallet);
  });

  it('knows the older contracts by the hash of their code BOC', () => {
    const contract = findKnownContract(undefined, '5659ce2300f4a09a37b0bdee41246ded52474f032c1d6ffce0d7d31b18b7b2b1');

    expect(contract?.name).toBe('v4R2');
    expect(contract?.type).toBe(ContractType.Wallet);
  });

  it('tells a contract it knows from a wallet', () => {
    const contract = findKnownContract('8836d2f41b39cd2cbdd8a66c10f9665d075242a66003bd8f14485bd6b140d303');

    expect(contract?.name).toBe('stonPtonWallet');
    expect(contract?.type).not.toBe(ContractType.Wallet);
  });

  it.each(Object.entries(walletClassMap))('knows the code the app builds for %s', (version, WalletClass) => {
    const { code } = WalletClass.create({ workchain: 0, publicKey: Buffer.alloc(32) }).init;

    expect(findKnownContract(code.hash().toString('hex'))?.name).toBe(version);
  });

  it('gives nothing for code it does not know', () => {
    expect(findKnownContract('00'.repeat(32), '11'.repeat(32))).toBeUndefined();
  });

  it('gives nothing for an address with no code, where both hashes are empty', () => {
    expect(findKnownContract('', '')).toBeUndefined();
  });
});
