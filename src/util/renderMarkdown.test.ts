import renderMarkdown, { parseMarkdownActions } from './renderMarkdown';

describe('renderMarkdown action links', () => {
  it('separates complete action links from renderable text', () => {
    expect(parseMarkdownActions([
      'Done.',
      '',
      '[Open Agent](mtw://agent)',
      '[Swap](mtw://swap)',
    ].join('\n'))).toEqual({
      buttons: [
        { label: 'Open Agent', url: 'mtw://agent' },
        { label: 'Swap', url: 'mtw://swap' },
      ],
      renderableText: 'Done.\n\n\n',
    });
  });

  it.each([
    '[',
    '[Open Agent',
    '[Open Agent]',
    '[Open Agent](',
    '[Open Agent](mtw:',
    '[Open Agent](mtw://agent',
  ])('buffers an incomplete trailing action token: %s', (action) => {
    expect(parseMarkdownActions(`Done.\n\n${action}`, {
      shouldBufferIncompleteAction: true,
    })).toEqual({
      buttons: [],
      renderableText: 'Done.\n\n',
    });
  });

  it('releases a trailing bracket expression after it stops matching an action', () => {
    expect(parseMarkdownActions('Use [optional] value', {
      shouldBufferIncompleteAction: true,
    }).renderableText).toBe('Use [optional] value');
  });

  it('preserves regular Markdown links', () => {
    expect(parseMarkdownActions('[Website](https://example.com)', {
      shouldBufferIncompleteAction: true,
    })).toEqual({
      buttons: [],
      renderableText: '[Website](https://example.com)',
    });

    const result = renderMarkdown('[Website](https://example.com)', {
      shouldBufferIncompleteAction: true,
    });

    expect(result.renderableText).toBe('[Website](https://example.com)');
    expect(result.html).toContain('<a href="https://example.com"');
    expect(result.buttons).toEqual([]);
  });
});
