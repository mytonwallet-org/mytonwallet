import type { ApiTokenWithPrice } from '../types';
import type { Repository } from './types';

import { tokenRepository as dexieTokenRepository } from './dexie';
import { createNoopRepository } from './noopRepository';

export type { ApiDbNft, ApiDbSseConnection } from './types';

/**
 * Air keeps its state in native storage and never reads this cache back. With `IS_AIR_APP` folded to a
 * literal, the Dexie repository is left unreferenced and tree-shaking drops it with the `dexie` dependency.
 */
export const tokenRepository: Repository<ApiTokenWithPrice> = process.env.IS_AIR_APP === '1'
  ? createNoopRepository<ApiTokenWithPrice>()
  : dexieTokenRepository;
