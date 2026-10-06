import type { UtxoAddressInfo, UtxoTransaction } from './types';

jest.mock('../../../util/fetch', () => ({ fetchJson: jest.fn() }));

import { fetchJson } from '../../../util/fetch';
import {
  getTokenActivitySlice,
  parseUtxoTransaction,
  resolveBlockbookAddressTransactions,
} from './activities';

const BTC_ADDRESS = 'bc1qvmw9dmensxtuxu5vw7mxtxqurad2u99pdj9wwa';
const LTC_ADDRESS = 'ltc1qvmw9dmensxtuxu5vw7mxtxqurad2u99m9cqgtp';
const WALLET_PAYLOAD = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';
const WALLET_PREFIXED = `bitcoincash:${WALLET_PAYLOAD}`;
const WALLET_LEGACY = '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu';
const COUNTERPARTY_PAYLOAD = 'qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy';
const COUNTERPARTY_PREFIXED = `bitcoincash:${COUNTERPARTY_PAYLOAD}`;

const ZEC_SENDER = 't1Yu7eHTifSqttLD6X8trcqwDExs6TpL87o';
const ZEC_RECIPIENT = 't1JmzuDedzhWX7PavfsrUeVYvsEWr3i8BGs';

const ZEC_SENDER_OUTGOING_TX: UtxoTransaction = {
  txid: 'd0379a41d9b3c471a773c5600be0b0320b5a1145e0d42161e93ed21c16338b90',
  version: 5,
  confirmations: 39,
  blockTime: 1_790_778_446,
  fees: '10170',
  value: '862728',
  valueIn: '872898',
  vin: [{
    txid: 'c19d2dd68f4297fc7f77a79e207d104bf0fa7831b73676f24ecaba485fcb754e',
    n: 0,
    addresses: [ZEC_SENDER],
    isAddress: true,
    isOwn: true,
    value: '872898',
  }],
  vout: [
    {
      value: '100000',
      n: 0,
      addresses: [ZEC_RECIPIENT],
      isAddress: true,
    },
    {
      value: '762728',
      n: 1,
      addresses: [ZEC_SENDER],
      isAddress: true,
      isOwn: true,
    },
  ],
};

const ZEC_BLOCKBOOK_ADDRESS_TX: UtxoTransaction = {
  txid: 'd0379a41d9b3c471a773c5600be0b0320b5a1145e0d42161e93ed21c16338b90',
  version: 5,
  confirmations: 17,
  blockTime: 1_790_778_446,
  fees: '10170',
  value: '862728',
  valueIn: '872898',
  vin: [{
    txid: 'c19d2dd68f4297fc7f77a79e207d104bf0fa7831b73676f24ecaba485fcb754e',
    sequence: 4294967295,
    n: 0,
    addresses: [ZEC_SENDER],
    isAddress: true,
    value: '872898',
  }],
  vout: [
    {
      value: '100000',
      n: 0,
      addresses: [ZEC_RECIPIENT],
      isAddress: true,
      isOwn: true,
    },
    {
      value: '762728',
      n: 1,
      addresses: [ZEC_SENDER],
      isAddress: true,
    },
  ],
};

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

describe('resolveBlockbookAddressTransactions', () => {
  it('falls back to txids when Blockbook returns an empty transactions array', async () => {
    const fetchedTx: UtxoTransaction = { ...ZEC_BLOCKBOOK_ADDRESS_TX, txid: 'fetched' };
    jest.mocked(fetchJson).mockResolvedValue(fetchedTx);

    const result = await resolveBlockbookAddressTransactions(
      'zcash',
      'mainnet',
      {
        address: ZEC_RECIPIENT,
        balance: '100000',
        txs: 1,
        txids: ['fetched'],
        transactions: [],
      } as UtxoAddressInfo,
    );

    expect(result).toEqual([fetchedTx]);
    expect(fetchJson).toHaveBeenCalledWith(
      expect.stringContaining('/api/v2/tx/fetched'),
    );
  });
});

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

  it('parses Zcash incoming address-scoped Blockbook txs', () => {
    const activity = parseUtxoTransaction('zcash', 'mainnet', ZEC_RECIPIENT, ZEC_BLOCKBOOK_ADDRESS_TX);

    expect(activity.isIncoming).toBe(true);
    expect(activity.amount).toBe(100000n);
    expect(activity.shouldHide).toBe(false);
    expect(activity.fromAddress).toBe(ZEC_SENDER);
    expect(activity.toAddress).toBe(ZEC_RECIPIENT);
    expect(activity.slug).toBe('zec');
  });

  it('parses Zcash outgoing send with change and isOwn vin from sender address history', () => {
    const activity = parseUtxoTransaction('zcash', 'mainnet', ZEC_SENDER, ZEC_SENDER_OUTGOING_TX);

    expect(activity.isIncoming).toBe(false);
    expect(activity.amount).toBe(-100000n);
    expect(activity.shouldHide).toBe(false);
    expect(activity.fromAddress).toBe(ZEC_SENDER);
    expect(activity.toAddress).toBe(ZEC_RECIPIENT);
  });

  it('recognizes Zcash isOwn outputs even when addresses are omitted', () => {
    const txWithoutOwnAddresses: UtxoTransaction = {
      ...ZEC_BLOCKBOOK_ADDRESS_TX,
      vout: [
        { value: '100000', n: 0, isOwn: true },
        { value: '762728', n: 1, addresses: [ZEC_SENDER], isAddress: true },
      ],
    };

    const activity = parseUtxoTransaction('zcash', 'mainnet', ZEC_RECIPIENT, txWithoutOwnAddresses);

    expect(activity.isIncoming).toBe(true);
    expect(activity.amount).toBe(100000n);
    expect(activity.shouldHide).toBe(false);
    expect(activity.toAddress).toBe(ZEC_RECIPIENT);
  });
});

describe('getTokenActivitySlice', () => {
  beforeEach(() => {
    jest.mocked(fetchJson).mockReset();
  });

  it('returns both Zcash address-scoped transactions from Blockbook', async () => {
    jest.mocked(fetchJson).mockResolvedValue({
      page: 1,
      totalPages: 1,
      transactions: [ZEC_SENDER_OUTGOING_TX, {
        ...ZEC_SENDER_OUTGOING_TX,
        txid: 'c19d2dd68f4297fc7f77a79e207d104bf0fa7831b73676f24ecaba485fcb754e',
        blockTime: 1_790_615_571,
        vin: [{
          txid: '114934b6bd0a6e398b60a61da7b2815a6cbf52efc46cfa12e1cdb44a43cb3f9d',
          n: 0,
          addresses: ['t1eorQMXjbVtzmPAdYq8cBD8XH7Ju7H9Ass'],
          value: '1400000',
        }],
        vout: [{
          value: '872898',
          n: 0,
          addresses: [ZEC_SENDER],
          isAddress: true,
          isOwn: true,
        }],
        value: '24322331',
        valueIn: '24337331',
      }],
    });

    const { activities, hasMore } = await getTokenActivitySlice(
      'zcash',
      'mainnet',
      ZEC_SENDER,
      undefined,
      undefined,
      100,
    );

    expect(hasMore).toBe(false);
    expect(activities).toHaveLength(2);
    expect(activities.map((activity) => activity.id)).toEqual([
      'd0379a41d9b3c471a773c5600be0b0320b5a1145e0d42161e93ed21c16338b90',
      'c19d2dd68f4297fc7f77a79e207d104bf0fa7831b73676f24ecaba485fcb754e',
    ]);
    expect((activities[0] as any).amount).toBe(-100000n);
    expect((activities[1] as any).amount).toBe(872898n);
  });
});
