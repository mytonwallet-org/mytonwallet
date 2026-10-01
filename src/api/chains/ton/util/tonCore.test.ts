import { Address, Builder, Cell } from '@ton/core';

import {
  fetchTokenAddress,
  fetchTokenWallet,
  packBytesAsSnakeCell,
  packBytesAsSnakeForEncryptedData,
  toBase64Address,
} from './tonCore';

const mockOpen = jest.fn();

jest.mock('../../../environment', () => ({
  getEnvironment: () => ({
    apiHeaders: undefined,
    byNetwork: {
      mainnet: { toncenterUrl: 'https://toncenter.example/' },
      testnet: { toncenterUrl: 'https://toncenter.example/' },
    },
  }),
}));

jest.mock('./TonClient', () => ({
  TonClient: jest.fn().mockImplementation(() => ({
    open: (contract: unknown) => mockOpen(contract),
  })),
}));

const CELL_CAPACITY = 127;
const TOKEN_WALLET_ADDRESS = `0:${'1'.repeat(64)}`;
const OTHER_TOKEN_WALLET_ADDRESS = `0:${'2'.repeat(64)}`;
const OWNER_ADDRESS = `0:${'3'.repeat(64)}`;
const MINTER_ADDRESS = `0:${'5'.repeat(64)}`;

describe('fetchTokenWallet', () => {
  beforeEach(() => {
    mockOpen.mockReset();
  });

  it('returns the minter and owner of a wallet derived by that minter for the reported owner', async () => {
    mockTokenWalletContracts(TOKEN_WALLET_ADDRESS);

    const result = await fetchTokenWallet('mainnet', TOKEN_WALLET_ADDRESS);

    expect(result).toEqual({
      tokenAddress: toBase64Address(MINTER_ADDRESS, true, 'mainnet'),
      ownerAddress: toBase64Address(OWNER_ADDRESS, undefined, 'mainnet'),
    });
  });

  it('rejects a wallet that reports a minter which derives a different address', async () => {
    mockTokenWalletContracts(OTHER_TOKEN_WALLET_ADDRESS);

    await expect(fetchTokenWallet('mainnet', TOKEN_WALLET_ADDRESS))
      .rejects.toThrow('Invalid jetton wallet contract');
  });
});

describe('fetchTokenAddress', () => {
  beforeEach(() => {
    mockOpen.mockReset();
  });

  it('returns the reported minter with a single request to the wallet', async () => {
    mockTokenWalletContracts(TOKEN_WALLET_ADDRESS);

    const result = await fetchTokenAddress('mainnet', TOKEN_WALLET_ADDRESS);

    expect(result).toBe(toBase64Address(MINTER_ADDRESS, true, 'mainnet'));
    expect(mockOpen).toHaveBeenCalledTimes(1);
  });
});

describe('packBytesAsSnakeCell', () => {
  it('turns empty bytes into an empty cell', () => {
    const result = packBytesAsSnakeCell(new Uint8Array([]));
    expectCellsToEqual(result, Cell.EMPTY);
  });

  it('turns a short payload into a single cell', () => {
    const payload = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit';
    const result = packBytesAsSnakeCell(Buffer.from(payload));
    expectCellsToEqual(result, createCell(payload));
  });

  it('turns a long payload into a snake cell', () => {
    const payload = 'Donec vulputate rutrum ex, ut accumsan lorem lacinia id. Pellentesque sit amet dignissim justo.'
      + ' Nam imperdiet tellus turpis, at congue neque rhoncus sit amet. Suspendisse magna augue, tincidunt ac porta'
      + ' volutpat, condimentum id sapien. Mauris efficitur eros ut orci euismod, nec varius erat ullamcorper. Proin'
      + ' nunc dui, vestibulum a consectetur in, maximus a enim. Mauris leo nunc, vestibulum lobortis nisl eleifend,'
      + ' pulvinar malesuada mauris. Duis cursus odio pellentesque enim bibendum gravida. Proin euismod tempor neque.'
      + ' Aenean ipsum ligula, accumsan a justo vitae, fermentum congue risus. Vestibulum vitae nunc a magna tempus'
      + ' fringilla id vitae ligula. Pellentesque tortor tortor, fringilla id sem quis, porttitor feugiat lectus.'
      + ' Curabitur ullamcorper urna diam, vitae convallis nulla maximus ac.';
    const result = packBytesAsSnakeCell(Buffer.from(payload));
    expectCellsToEqual(
      result,
      createCell(payload.slice(0, CELL_CAPACITY),
        createCell(payload.slice(CELL_CAPACITY, CELL_CAPACITY * 2),
          createCell(payload.slice(CELL_CAPACITY * 2, CELL_CAPACITY * 3),
            createCell(payload.slice(CELL_CAPACITY * 3, CELL_CAPACITY * 4),
              createCell(payload.slice(CELL_CAPACITY * 4, CELL_CAPACITY * 5),
                createCell(payload.slice(CELL_CAPACITY * 5, CELL_CAPACITY * 6),
                  createCell(payload.slice(CELL_CAPACITY * 6)))))))),
    );
  });

  it('respects the byte offset and length of the input Uint8Array', () => {
    const payload = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi aliquam vehicula tellus non'
      + ' vehicula. Praesent dictum, tellus aliquet bibendum dapibus, ipsum massa tempus diam, id auctor ligula dui et'
      + ' orci. Ut consequat congue ipsum, in mattis lectus dignissim efficitur.';
    const payloadBuffer = Buffer.from(payload).buffer;
    const startOffset = 8;
    const endOffset = 11;
    const input = new Uint8Array(payloadBuffer, startOffset, payload.length - startOffset - endOffset);
    const result = packBytesAsSnakeCell(input);
    expectCellsToEqual(
      result,
      createCell(payload.slice(startOffset, startOffset + CELL_CAPACITY),
        createCell(payload.slice(startOffset + CELL_CAPACITY, payload.length - endOffset))),
    );
  });
});

describe('packBytesAsSnakeForEncryptedData', () => {
  it('packs a short payload into a cell with an empty tail', () => {
    const payload = 'Hello, world';
    const result = packBytesAsSnakeForEncryptedData(Buffer.from(payload));
    expectCellsToEqual(result, createCell(payload, createCell('')));
  });

  it('packs a long payload into a snake cell', () => {
    const payload = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi aliquam vehicula tellus non'
      + ' vehicula. Praesent dictum, tellus aliquet bibendum dapibus, ipsum massa tempus diam, id auctor ligula dui et'
      + ' orci.';
    const result = packBytesAsSnakeForEncryptedData(Buffer.from(payload));
    const firstCellCapacity = 39;
    expectCellsToEqual(
      result,
      createCell(payload.slice(0, firstCellCapacity),
        createCell(payload.slice(firstCellCapacity, firstCellCapacity + CELL_CAPACITY),
          createCell(payload.slice(firstCellCapacity + CELL_CAPACITY)))),
    );
  });

  it('throws if there are too much data', () => {
    const payload = new Uint8Array(2200);
    expect(() => packBytesAsSnakeForEncryptedData(payload)).toThrow('Input text is too long');
  });
});

function expectCellsToEqual(actual: Cell, expected: Cell) {
  expect(actual.toString()).toBe(expected.toString());
}

function createCell(payload: string, tail?: Cell) {
  const builder = new Builder().storeBuffer(Buffer.from(payload));
  if (tail) {
    builder.storeRef(tail);
  }
  return builder.endCell();
}

function mockTokenWalletContracts(derivedWalletAddress: string) {
  mockOpen
    .mockReturnValueOnce({
      getWalletData: jest.fn().mockResolvedValue({
        balance: 1n,
        owner: Address.parse(OWNER_ADDRESS),
        minter: Address.parse(MINTER_ADDRESS),
        code: Cell.EMPTY,
      }),
    })
    .mockReturnValueOnce({
      getWalletAddress: jest.fn().mockResolvedValue(Address.parse(derivedWalletAddress)),
    });
}
