import { Address, NETWORK, TEST_NETWORK } from '@scure/btc-signer';

import { toUtxoSignerAddress } from './address';
import {
  bitcoinCashAddressToPayload,
  cashAddrPayloadToLegacy,
  decodeCashAddress,
  encodeCashAddress,
} from './cashaddr';

const SPEC_VECTORS: Array<{
  legacy: string;
  cashaddr: string;
  type: 'p2pkh' | 'p2sh';
}> = [
  {
    legacy: '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu',
    cashaddr: 'bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a',
    type: 'p2pkh',
  },
  {
    legacy: '1KXrWXciRDZUpQwQmuM1DbwsKDLYAYsVLR',
    cashaddr: 'bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy',
    type: 'p2pkh',
  },
  {
    legacy: '16w1D5WRVKJuZUsSRzdLp9w3YGcgoxDXb',
    cashaddr: 'bitcoincash:qqq3728yw0y47sqn6l2na30mcw6zm78dzqre909m2r',
    type: 'p2pkh',
  },
  {
    legacy: '3CWFddi6m4ndiGyKqzYvsFYagqDLPVMTzC',
    cashaddr: 'bitcoincash:ppm2qsznhks23z7629mms6s4cwef74vcwvn0h829pq',
    type: 'p2sh',
  },
  {
    legacy: '3LDsS579y7sruadqu11beEJoTjdFiFCdX4',
    cashaddr: 'bitcoincash:pr95sy3j9xwd2ap32xkykttr4cvcu7as4yc93ky28e',
    type: 'p2sh',
  },
  {
    legacy: '31nwvkZwyPdgzjBJZXfDmSWsC4ZLKpYyUw',
    cashaddr: 'bitcoincash:pqq3728yw0y47sqn6l2na30mcw6zm78dzq5ucqzc37',
    type: 'p2sh',
  },
];

describe('cashaddr', () => {
  it.each(SPEC_VECTORS)('roundtrips $type $legacy', ({ legacy, cashaddr, type }) => {
    const decodedLegacy = Address(NETWORK).decode(legacy);
    const encoded = encodeCashAddress('bitcoincash', type, (decodedLegacy as any).hash);
    const decoded = decodeCashAddress(cashaddr);

    expect(encoded).toBe(cashaddr);
    expect(decoded.type).toBe(type);
    expect(Buffer.from((decoded as any).hash)).toEqual(Buffer.from((decodedLegacy as any).hash));
    expect(cashAddrPayloadToLegacy('mainnet', cashaddr.split(':')[1])).toBe(legacy);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', cashaddr.split(':')[1])).toBe(legacy);
    expect(toUtxoSignerAddress('bitcoincash', 'mainnet', cashaddr)).toBe(legacy);
  });

  it.each(SPEC_VECTORS)('converts $type $legacy to a payload', ({ legacy, cashaddr }) => {
    const payload = cashaddr.split(':')[1];

    expect(bitcoinCashAddressToPayload('mainnet', legacy)).toBe(payload);
    expect(bitcoinCashAddressToPayload('mainnet', cashaddr)).toBe(payload);
    expect(bitcoinCashAddressToPayload('mainnet', payload)).toBe(payload);
  });

  it('decodes the 20-byte hash test vector', () => {
    const decoded = decodeCashAddress('bitcoincash:qr6m7j9njldwwzlg9v7v53unlr4jkmx6eylep8ekg2');

    expect(decoded.type).toBe('p2pkh');
    expect(Buffer.from(decoded.hash).toString('hex')).toBe('f5bf48b397dae70be82b3cca4793f8eb2b6cdac9');
  });

  it('encodes testnet cashaddr with testnet version bytes', () => {
    const hash = (Address(NETWORK).decode('1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu') as any).hash;
    const payload = encodeCashAddress('bchtest', 'p2pkh', hash).split(':')[1];

    expect(cashAddrPayloadToLegacy('testnet', payload)).toBe(
      Address(TEST_NETWORK).encode({ type: 'pkh', hash }),
    );
  });

  it('rejects unknown cashaddr types', () => {
    expect(() => decodeCashAddress('prefix:0r6m7j9njldwwzlg9v7v53unlr4jkmx6ey3qnjwsrf'))
      .toThrow('Unsupported cashaddr type');
  });
});
