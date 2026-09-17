import type { UtxoTransaction } from './types';

import { parseUtxoTransaction } from './activities';

const BTC_ADDRESS = 'bc1qvmw9dmensxtuxu5vw7mxtxqurad2u99pdj9wwa';
const LTC_ADDRESS = 'ltc1qvmw9dmensxtuxu5vw7mxtxqurad2u99m9cqgtp';
const WALLET_PAYLOAD = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';
const WALLET_PREFIXED = `bitcoincash:${WALLET_PAYLOAD}`;
const WALLET_LEGACY = '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu';
const COUNTERPARTY_PAYLOAD = 'qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy';
const COUNTERPARTY_PREFIXED = `bitcoincash:${COUNTERPARTY_PAYLOAD}`;

function tx(confirmations: number, walletAddress = BTC_ADDRESS): UtxoTransaction {
  return {
    txid: 'a'.repeat(64),
    confirmations,
    blockTime: 1_700_000_000,
    fees: '100',
    vin: [{ addresses: ['bc1qsender000000000000000000000000000000000'], value: '1000' }],
    vout: [{ addresses: [walletAddress], value: '900', n: 0 }],
  };
}

function incomingTx(outputAddress: string): UtxoTransaction {
  return {
    txid: 'incoming',
    blockTime: 1_700_000_000,
    confirmations: 1,
    fees: '1000',
    vin: [{ addresses: [COUNTERPARTY_PREFIXED], value: '200000' }],
    vout: [{ n: 0, value: '199000', addresses: [outputAddress] }],
  };
}

function outgoingTx(changeAddress: string): UtxoTransaction {
  return {
    txid: 'outgoing',
    blockTime: 1_700_000_000,
    confirmations: 1,
    fees: '1000',
    vin: [{ addresses: [WALLET_PREFIXED], value: '200000' }],
    vout: [
      { n: 0, value: '50000', addresses: [COUNTERPARTY_PREFIXED] },
      { n: 1, value: '149000', addresses: [changeAddress] },
    ],
  };
}

describe('parseUtxoTransaction', () => {
  it('keeps Bitcoin unconfirmed transactions pending and exposes confirmations', () => {
    expect(parseUtxoTransaction('bitcoin', 'mainnet', BTC_ADDRESS, tx(0))).toMatchObject({
      status: 'pending',
      confirmations: 0,
      maxConfirmations: 2,
    });
  });

  it('uses the documented REST fallback finality for Bitcoin transactions', () => {
    expect(parseUtxoTransaction('bitcoin', 'mainnet', BTC_ADDRESS, tx(1))).toMatchObject({
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
    });
    expect(parseUtxoTransaction('bitcoin', 'mainnet', BTC_ADDRESS, tx(2))).toMatchObject({
      status: 'completed',
      confirmations: 2,
      maxConfirmations: 2,
    });
  });

  it('uses the same REST fallback for non-Bitcoin UTXO transactions', () => {
    expect(parseUtxoTransaction('litecoin', 'mainnet', LTC_ADDRESS, tx(1, LTC_ADDRESS))).toMatchObject({
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
    });
    expect(parseUtxoTransaction('litecoin', 'mainnet', LTC_ADDRESS, tx(2, LTC_ADDRESS))).toMatchObject({
      status: 'completed',
      confirmations: 2,
      maxConfirmations: 2,
    });
  });

  it('treats cashaddr and legacy bitcoin cash outputs as the same wallet', () => {
    for (const outputAddress of [WALLET_PAYLOAD, WALLET_PREFIXED, WALLET_LEGACY]) {
      const activity = parseUtxoTransaction('bitcoincash', 'mainnet', WALLET_PAYLOAD, incomingTx(outputAddress));

      expect(activity.isIncoming).toBe(true);
      expect(activity.amount).toBe(199000n);
      expect(activity.shouldHide).toBe(false);
      expect(activity.fromAddress).toBe(COUNTERPARTY_PAYLOAD);
      expect(activity.toAddress).toBe(WALLET_PAYLOAD);
      expect(activity.normalizedAddress).toBe(WALLET_PAYLOAD);
    }
  });

  it('subtracts change when the change output uses a different address format', () => {
    const activity = parseUtxoTransaction(
      'bitcoincash',
      'mainnet',
      WALLET_PAYLOAD,
      outgoingTx(WALLET_LEGACY),
    );

    expect(activity.isIncoming).toBe(false);
    expect(activity.amount).toBe(-50000n);
    expect(activity.fromAddress).toBe(WALLET_PAYLOAD);
    expect(activity.toAddress).toBe(COUNTERPARTY_PAYLOAD);
    expect(activity.normalizedAddress).toBe(WALLET_PAYLOAD);
  });
});
