import { createStore, delMany } from 'idb-keyval';

import { INDEXED_DB_NAME, INDEXED_DB_STORE_NAME } from '../../config';
import clearLegacyAgentStorage from './clearLegacyAgentStorage';

jest.mock('idb-keyval', () => ({
  createStore: jest.fn(() => jest.fn()),
  delMany: jest.fn(() => Promise.resolve()),
}));

it('removes only retired Agent history and identity from the wallet database', async () => {
  await clearLegacyAgentStorage();

  expect(createStore).toHaveBeenCalledWith(INDEXED_DB_NAME, INDEXED_DB_STORE_NAME);
  expect(delMany).toHaveBeenCalledTimes(1);
  expect(delMany).toHaveBeenCalledWith(
    ['agentMessages', 'agentConversationId'],
    jest.mocked(createStore).mock.results[0].value,
  );
});
