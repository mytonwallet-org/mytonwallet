import type { AgentMessage } from '../../../global/types';

import buildMessageTurnIds from './buildMessageTurnIds';

describe('buildMessageTurnIds', () => {
  it('starts a turn at each outgoing message and keeps a preceding date separator with it', () => {
    const messagesById = buildMessagesById([
      [1, false],
      [2, true],
      [3, false],
      [4, true],
      [5, false],
      [6, false],
    ]);
    const ids = ['date:1', '1', '2', '3', 'date:4', '4', '5', 'date:6', '6'];

    expect(buildMessageTurnIds(ids, messagesById)).toEqual({
      'date:1': '1',
      1: '1',
      2: '2',
      3: '2',
      'date:4': '4',
      4: '4',
      5: '4',
      'date:6': '4',
      6: '4',
    });
  });

  it('keeps existing turn ids when a new question is appended', () => {
    const messagesById = buildMessagesById([
      [1, true],
      [2, false],
      [3, true],
      [4, false],
      [5, true],
    ]);
    const ids = ['date:1', '1', '2', '3', '4'];

    expect(buildMessageTurnIds(ids, messagesById)).toEqual(
      expect.objectContaining({ 2: '1', 4: '3' }),
    );
    expect(buildMessageTurnIds([...ids, '5'], messagesById)).toEqual(
      expect.objectContaining({ 2: '1', 4: '3', 5: '5' }),
    );
  });

  it('keeps a turn named when older history takes the date line that opened it', () => {
    const messagesById = buildMessagesById([
      [1, true],
      [2, false],
      [3, true],
      [4, false],
    ]);

    expect(buildMessageTurnIds(['date:3', '3', '4'], messagesById)).toEqual({ 'date:3': '3', 3: '3', 4: '3' });
    expect(buildMessageTurnIds(['date:1', '1', '2', '3', '4'], messagesById)).toEqual(
      expect.objectContaining({ 3: '3', 4: '3' }),
    );
  });

  it('makes each answer that no question comes before a turn of its own, as a news item', () => {
    const messagesById = buildMessagesById([
      [1, false],
      [2, false],
      [3, false],
    ]);

    expect(buildMessageTurnIds(['date:1', '1', '2', 'date:3', 'unread:3', '3'], messagesById)).toEqual({
      'date:1': '1',
      1: '1',
      2: '2',
      'date:3': '3',
      'unread:3': '3',
      3: '3',
    });
  });

  it('keeps the "New" line with the message after it, inside or at the start of a turn', () => {
    const messagesById = buildMessagesById([
      [1, true],
      [2, false],
      [3, true],
      [4, false],
    ]);

    expect(buildMessageTurnIds(['date:1', '1', 'unread:2', '2', '3', '4'], messagesById)).toEqual(
      expect.objectContaining({ 'unread:2': '1', 2: '1' }),
    );
    expect(buildMessageTurnIds(['date:1', '1', '2', 'unread:3', '3', '4'], messagesById)).toEqual(
      expect.objectContaining({ 'unread:3': '3', 3: '3' }),
    );
  });
});

function buildMessagesById(entries: [number, boolean][]) {
  return Object.fromEntries(entries.map(([id, isOutgoing]): [number, AgentMessage] => [id, {
    id,
    text: `Message ${id}`,
    isOutgoing,
    timestamp: id,
  }]));
}
