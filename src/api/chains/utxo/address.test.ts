import { isSameUtxoAddress, isValidAddress, normalizeAddress, toUtxoSignerAddress } from './address';

describe('UTXO address validation', () => {
  it('accepts mainnet bitcoin bech32 and rejects testnet on mainnet', () => {
    expect(isValidAddress('bitcoin', 'mainnet', 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq')).toBe(true);
    expect(isValidAddress('bitcoin', 'mainnet', 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx')).toBe(false);
  });

  it('accepts bitcoin cash payloads and prefixed cashaddr', () => {
    const payload = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';
    const prefixed = `bitcoincash:${payload}`;

    expect(isValidAddress('bitcoincash', 'mainnet', payload)).toBe(true);
    expect(isValidAddress('bitcoincash', 'mainnet', prefixed)).toBe(true);
    expect(isValidAddress('bitcoincash', 'mainnet', `BITCOINCASH:${payload.toUpperCase()}`)).toBe(true);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', prefixed)).toBe('1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu');
    expect(normalizeAddress('bitcoincash', prefixed, 'mainnet')).toBe(payload);
    expect(isSameUtxoAddress('bitcoincash', 'mainnet', payload, prefixed)).toBe(true);
    expect(isSameUtxoAddress('bitcoincash', 'mainnet', payload, '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu')).toBe(true);
  });

  it('rejects bitcoin cash addresses from the other network', () => {
    expect(isValidAddress('bitcoincash', 'testnet', 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a')).toBe(false);
    expect(isValidAddress('bitcoincash', 'mainnet', 'bchtest:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a')).toBe(false);
  });

  it('accepts bitcoin cash legacy p2pkh and rejects bitcoin witness addresses', () => {
    const legacy = '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu';

    expect(isValidAddress('bitcoincash', 'mainnet', legacy)).toBe(true);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', legacy)).toBe(legacy);
    expect(normalizeAddress('bitcoincash', legacy, 'mainnet')).toBe('qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a');
    expect(isValidAddress('bitcoincash', 'mainnet', 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq')).toBe(false);
    expect(isValidAddress(
      'bitcoincash',
      'mainnet',
      'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297',
    )).toBe(false);
    expect(() => toUtxoSignerAddress('bitcoincash', 'mainnet', 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'))
      .toThrow('Bitcoin Cash does not support this address type');
  });

  it('accepts a checksummed litecoin fee-check address', () => {
    expect(isValidAddress('litecoin', 'mainnet', 'ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7kgmn4n9')).toBe(true);
  });

  it('accepts the bitcoin cash fee-check payload and prefixed cashaddr for signing', () => {
    const payload = 'qrny4xkwvwvsxertkd2nue70wmc5s98kru7m2q7vk6';
    const prefixed = `bitcoincash:${payload}`;
    const legacy = '1MzfnkLjEAVdjAg8somKu7a7LWpRc1kSop';

    expect(isValidAddress('bitcoincash', 'mainnet', payload)).toBe(true);
    expect(isValidAddress('bitcoincash', 'mainnet', prefixed)).toBe(true);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', payload)).toBe(legacy);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', prefixed)).toBe(legacy);
    expect(normalizeAddress('bitcoincash', prefixed, 'mainnet')).toBe(payload);
  });
});
