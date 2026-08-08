import { segmentStreamingMarkdown } from './streamingMarkdown';

describe('segmentStreamingMarkdown', () => {
  it('commits blocks only after an empty line', () => {
    expect(segmentStreamingMarkdown('First paragraph.\n\nSecond paragraph')).toEqual({
      blocks: [{ offset: 0, text: 'First paragraph.\n' }],
      tail: 'Second paragraph',
    });
  });

  it('keeps completed paragraphs stable while the next paragraph grows and preserves completed order', () => {
    const initial = segmentStreamingMarkdown(
      'First paragraph.\n\nSecond paragraph.\n\nThird',
    );
    const updated = segmentStreamingMarkdown(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.',
    );

    expect(initial).toEqual({
      blocks: [
        { offset: 0, text: 'First paragraph.\n' },
        { offset: 18, text: 'Second paragraph.\n' },
      ],
      tail: 'Third',
    });
    expect(updated.blocks).toEqual(initial.blocks);
    expect(updated.tail).toBe('Third paragraph.');

    expect(segmentStreamingMarkdown(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.',
      true,
    )).toEqual({
      blocks: [
        { offset: 0, text: 'First paragraph.\n' },
        { offset: 18, text: 'Second paragraph.\n' },
        { offset: 37, text: 'Third paragraph.' },
      ],
      tail: '',
    });
  });

  it('keeps empty lines inside a fenced code block in the mutable tail', () => {
    const text = '```ts\nconst value = 1;\n\nconst next = 2;\n```\n\nAfter';

    expect(segmentStreamingMarkdown(text)).toEqual({
      blocks: [{
        offset: 0,
        text: '```ts\nconst value = 1;\n\nconst next = 2;\n```\n',
      }],
      tail: 'After',
    });
  });

  it('keeps loose consecutive list items in one block', () => {
    const text = '- First\n\n- Second\n\nAfter';

    expect(segmentStreamingMarkdown(text)).toEqual({
      blocks: [{
        offset: 0,
        text: '- First\n\n- Second\n',
      }],
      tail: 'After',
    });
  });

  it('keeps table rows together', () => {
    const text = '| A | B |\n| - | - |\n| 1 | 2 |\n\nTail';

    expect(segmentStreamingMarkdown(text)).toEqual({
      blocks: [{
        offset: 0,
        text: '| A | B |\n| - | - |\n| 1 | 2 |\n',
      }],
      tail: 'Tail',
    });
  });

  it('keeps incomplete Markdown syntax isolated in the tail', () => {
    const text = 'Stable paragraph.\n\n[unfinished link](https://example.com';

    expect(segmentStreamingMarkdown(text)).toEqual({
      blocks: [{ offset: 0, text: 'Stable paragraph.\n' }],
      tail: '[unfinished link](https://example.com',
    });
  });

  it('commits the remaining tail at visual completion', () => {
    const text = 'First paragraph.\n\nFinal paragraph.';

    expect(segmentStreamingMarkdown(text, true)).toEqual({
      blocks: [
        { offset: 0, text: 'First paragraph.\n' },
        { offset: 18, text: 'Final paragraph.' },
      ],
      tail: '',
    });
  });

  it('preserves source offsets after multiple empty lines', () => {
    const text = 'First.\n\n\nSecond.\n\nThird.';

    expect(segmentStreamingMarkdown(text)).toEqual({
      blocks: [
        { offset: 0, text: 'First.\n' },
        { offset: 9, text: 'Second.\n' },
      ],
      tail: 'Third.',
    });
  });
});
