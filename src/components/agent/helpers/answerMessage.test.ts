import type { AgentAnswerTableV1 } from '../../../api/agentV2/protocol/types';

import { getAnswerMessageCopyText } from './answerMessage';

const TABLE: AgentAnswerTableV1 = {
  id: 't1',
  content: { kind: 'display', headers: ['Value'], rows: [['1']], notes: [] },
};

describe('answer copy text', () => {
  it('keeps prose unchanged until a table reference reaches the available text', () => {
    expect(getAnswerMessageCopyText('🪙', [TABLE])).toBe('🪙');
    expect(getAnswerMessageCopyText('🪙', [TABLE], [{ tableId: 't1', textOffset: 4 }])).toBe('🪙');
    expect(getAnswerMessageCopyText('  plain text\n')).toBe('  plain text\n');
  });

  it('copies answer links after their labels and keeps tables where they were', () => {
    expect(getAnswerMessageCopyText('See Help.After Docs', [TABLE], [{ tableId: 't1', textOffset: 9 }], [
      { textOffset: 4, textLength: 4, url: 'https://help.mywallet.io/' },
      { textOffset: 15, textLength: 4, url: 'https://docs.example.com/' },
    ])).toBe('See Help (https://help.mywallet.io/).\n\nValue\n1\n\nAfter Docs (https://docs.example.com/)');
  });

  it('copies answer link labels without the escapes the server writes into them', () => {
    expect(getAnswerMessageCopyText('Use snake\\_case', undefined, undefined, [
      { textOffset: 4, textLength: 11, url: 'https://help.mywallet.io/' },
    ])).toBe('Use snake_case (https://help.mywallet.io/)');
    expect(getAnswerMessageCopyText('\\== rates', undefined, undefined, [
      { textOffset: 0, textLength: 3, url: 'https://help.mywallet.io/' },
    ])).toBe('== (https://help.mywallet.io/) rates');
  });

  it('copies every row and inserts consecutive tables in reference order', () => {
    const table: AgentAnswerTableV1 = { ...TABLE, content: {
      ...TABLE.content,
      rows: Array.from({ length: 12 }, (_, index) => [String(index + 1)]),
    } };
    const notes: AgentAnswerTableV1 = { id: 't2', content: {
      kind: 'display', headers: ['Ignored empty header'], rows: [], notes: ['No matches'],
    } };
    expect(getAnswerMessageCopyText('BeforeAfter', [notes, table], [
      { tableId: 't1', textOffset: 6 },
      { tableId: 't2', textOffset: 6 },
    ])).toBe('Before\n\nValue\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n\n\n\nNo matches\n\nAfter');
  });
});
