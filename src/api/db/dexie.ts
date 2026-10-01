import type { Table } from 'dexie';
import Dexie from 'dexie';

import type { ApiTokenWithPrice } from '../types';
import type { ApiDbNft } from './types';

import { DbRepository } from './repository';

const DB_NAME = 'tables';

export class ApiDb extends Dexie {
  nfts!: Table<ApiDbNft>;

  tokens!: Table<ApiTokenWithPrice>;

  constructor() {
    super(DB_NAME);
    this.version(1).stores({
      nfts: '[accountId+address], accountId, address, collectionAddress',
    });
    this.version(2).stores({
      sseConnections: '&clientId',
    });
    this.version(3).stores({
      tokens: 'tokenAddress, chain, &slug',
    });
    this.version(4).upgrade((tx) => {
      return tx.table('tokens').clear();
    });
    this.version(5).stores({
      // eslint-disable-next-line no-null/no-null
      nfts: null,
      // eslint-disable-next-line no-null/no-null
      sseConnections: null,
    });
    this.version(6).upgrade((tx) => {
      return tx.table<ApiTokenWithPrice & { price?: number }>('tokens').toCollection().modify((token) => {
        delete token.price;
      });
    });
    // A cached jetton image may be a direct link to the host chosen by the token issuer, which exposes the user's
    // IP address. The next token fetch replaces it with a Toncenter proxy link, or with no image at all.
    this.version(7).upgrade((tx) => {
      return tx.table<ApiTokenWithPrice>('tokens').toCollection().modify((token) => {
        if (token.chain === 'ton' && !token.isFromBackend) delete token.image;
      });
    });
  }
}

// Air never reads this cache, and its build must be able to drop this module together with the `dexie`
// package. `/* @__PURE__ */` lets the bundler delete the call below when `tokenRepository` is unused, but
// only the call itself: its arguments would still run. Written inline as
// `new DbRepository(new ApiDb().tokens)`, the database construction would stay in the bundle, so it lives
// inside a function that takes no arguments.
export const tokenRepository = /* @__PURE__ */ createTokenRepository();

function createTokenRepository() {
  return new DbRepository(new ApiDb().tokens);
}
