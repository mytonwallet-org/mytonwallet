import { closeStreamingInlineMarkdown, segmentStreamingMarkdown } from './streamingMarkdown';

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

describe('closeStreamingInlineMarkdown', () => {
  it('closes the bold, italics and code a growing paragraph has opened', () => {
    expect(closeStreamingInlineMarkdown('**Here is w')).toBe('**Here is w**');
    expect(closeStreamingInlineMarkdown('**Here is ')).toBe('**Here is** ');
    expect(closeStreamingInlineMarkdown('Fees are *high')).toBe('Fees are *high*');
    expect(closeStreamingInlineMarkdown('**Done** and *so')).toBe('**Done** and *so*');
    expect(closeStreamingInlineMarkdown('Run `npm')).toBe('Run `npm`');
  });

  it('waits for the rest of a marker that has come in only in part', () => {
    expect(closeStreamingInlineMarkdown('**Here is what I found*')).toBe('**Here is what I found**');
    expect(closeStreamingInlineMarkdown('**Here is what I found**')).toBe('**Here is what I found**');
    expect(closeStreamingInlineMarkdown('Your balance *')).toBe('Your balance');
    expect(closeStreamingInlineMarkdown('Your balance **')).toBe('Your balance');
    expect(closeStreamingInlineMarkdown('*Note*')).toBe('*Note*');
  });

  it('shows a link that is still coming in as its label', () => {
    expect(closeStreamingInlineMarkdown('See [the expl')).toBe('See the expl');
    expect(closeStreamingInlineMarkdown('See [the explorer](https://tonscan.o')).toBe('See the explorer');
    expect(closeStreamingInlineMarkdown('See [**the expl')).toBe('See **the expl**');
  });

  it('leaves out a marker with nothing after it yet and keeps closed markup and plain text as they are', () => {
    expect(closeStreamingInlineMarkdown('Run `')).toBe('Run ');
    expect(closeStreamingInlineMarkdown('**Done** and `code`')).toBe('**Done** and `code`');
    expect(closeStreamingInlineMarkdown('`a ** b` and **c')).toBe('`a ** b` and **c**');
    expect(closeStreamingInlineMarkdown('2 * 3 = 6 and snake_case')).toBe('2 * 3 = 6 and snake_case');
    expect(closeStreamingInlineMarkdown('* Fees are low')).toBe('* Fees are low');
    expect(closeStreamingInlineMarkdown('**Open\nNext line')).toBe('**Open\nNext line');
  });

  it('leaves an open code block as it is', () => {
    expect(closeStreamingInlineMarkdown('```\nconst a = **b')).toBe('```\nconst a = **b');
  });
});
