import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentAnswerTableV1 } from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';

import AnswerMessageContent from './AnswerMessageContent';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));

const TABLE: AgentAnswerTableV1 = { id: 't1', content: { kind: 'display',
  headers: ['Time', 'Network', 'Status', 'Amount'], notes: [],
  rows: [['2026-08-10T12:00:00.000Z', 'ton', 'Completed', '12.500000001 TON']],
} };

describe('inline answer tables', () => {
  let root: HTMLDivElement;
  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });
  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('reveals a table only at its text position and keeps it mounted as trailing text arrives', async () => {
    const tables = [TABLE];
    const tableReferences = [{ tableId: 't1', textOffset: 8 }];
    const render = async (text: string) => {
      TeactDOM.render(
        <AnswerMessageContent
          text={text}
          tables={tables}
          tableReferences={tableReferences}
          areLinksEnabled
        />, root);
      await pause(20);
    };
    await render('Before');
    expect(root.querySelector('table')).toBeNull();
    await render('Before\n\n');
    const element = root.querySelector('table');
    expect(element).not.toBeNull();
    expect(element?.textContent).toContain('12.500000001 TON');
    await render('Before\n\n\n\nAfter');
    expect(root.querySelector('table')).toBe(element);
    expect(root.textContent!.indexOf('Before')).toBeLessThan(root.textContent!.indexOf('12.500000001'));
    expect(root.textContent!.indexOf('After')).toBeGreaterThan(root.textContent!.indexOf('12.500000001'));
  });

  it('renders ready table cells and notes without domain mappings or interpreting their markup', async () => {
    const table: AgentAnswerTableV1 = { id: 't1', content: { kind: 'display',
      headers: ['Актив', 'Статус'], rows: [['[Token](mtw://send)', 'Ожидает подтверждения']],
      notes: ['Пропущено строк: 2'],
    } };
    TeactDOM.render(
      <AnswerMessageContent
        text=""
        tables={[table]}
        tableReferences={[{ tableId: 't1', textOffset: 0 }]}
        areLinksEnabled
      />, root);
    await pause(20);
    expect(root.querySelector('table')?.textContent).toContain('Ожидает подтверждения');
    expect(root.querySelector('table')?.textContent).toContain('[Token](mtw://send)');
    expect(root.textContent).toContain('Пропущено строк: 2');
    expect(root.querySelector('a')).toBeNull();
  });

  it('renders contact labels as text without executing HTML or interpreting Markdown', async () => {
    const table: AgentAnswerTableV1 = { id: 't1', content: { kind: 'display',
      headers: ['Name', 'Network', 'Address'], notes: [],
      rows: [['<img src=x onerror=alert(1)>', 'ton', '[link](https://example.com)']] } };
    TeactDOM.render(
      <AnswerMessageContent
        text=""
        tables={[table]}
        tableReferences={[{ tableId: 't1', textOffset: 0 }]}
        areLinksEnabled
      />, root);
    await pause(20);
    expect(root.querySelector('img, a')).toBeNull();
    expect(root.querySelector('table')?.textContent).toContain('[link](https://example.com)');
  });
});
