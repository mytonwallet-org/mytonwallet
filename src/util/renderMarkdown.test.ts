import { markAnswerLinks } from './agent/answerLinkMarkers';
import renderMarkdown, { renderDeterministicMarkdownTable } from './renderMarkdown';

describe('renderMarkdown', () => {
  it('renders answer links over their labels, as far as the revealed text goes', () => {
    const text = '- **Guide** and Docs';
    const links = [
      { textOffset: 2, textLength: 9, url: 'https://help.mywallet.io/a_(b)?x=*1*' },
      { textOffset: 16, textLength: 4, url: 'http://docs.example.com/' },
    ];

    expect(renderMarkdown(markAnswerLinks(text, links).text, { areLinksEnabled: true }).html).toBe(
      '<ul><li><a href="https://help.mywallet.io/a_(b)?x=*1*" target="_blank" rel="noopener noreferrer">'
      + '<strong>Guide</strong></a> and Docs</li></ul>',
    );
    expect(renderMarkdown(markAnswerLinks('- **Gu', links).text, { areLinksEnabled: true }).html)
      .toContain('<a href="https://help.mywallet.io/a_(b)?x=*1*"');
    expect(renderMarkdown(markAnswerLinks(text, links).text, { areLinksEnabled: false }).html)
      .toBe('<ul><li><strong>Guide</strong> (https://help.mywallet.io/a_(b)?x=*1*) and Docs</li></ul>');
    expect(renderMarkdown('A \uE004http%3A%2F%2Fa%2Eio\uE005B\uE006 C\uE006', { areLinksEnabled: true }).html)
      .toBe('<p>A B C</p>');
  });

  it('renders a link to a screen of the app and no other deeplink', () => {
    const text = 'Open Appearance, Send, Bonus or Gram';
    const links = [
      { textOffset: 5, textLength: 10, url: 'mtw://settings/appearance' },
      { textOffset: 17, textLength: 4, url: 'mtw://transfer' },
      { textOffset: 23, textLength: 5, url: 'mtw://r/bonus' },
      { textOffset: 32, textLength: 4, url: 'gramwallet://explore' },
    ];

    expect(renderMarkdown(markAnswerLinks(text, links).text, { areLinksEnabled: true }).html).toBe(
      '<p>Open <a href="mtw://settings/appearance" target="_blank" rel="noopener noreferrer">Appearance</a>, '
      + 'Send, Bonus or Gram</p>',
    );
  });

  it('reads an escaped equals sign as text', () => {
    expect(renderMarkdown('\\== rates', { areLinksEnabled: true }).html).toBe('<p>== rates</p>');
  });

  it('keeps answer link labels as text inside code', () => {
    const link = { textOffset: 19, textLength: 4, url: 'https://a.io/' };

    expect(renderMarkdown(markAnswerLinks('Prices in `USD\nsee Docs and `EUR`', [link]).text, {
      areLinksEnabled: true,
    }).html).toBe('<p>Prices in <code>USD see Docs and </code>EUR`</p>');
    expect(renderMarkdown(markAnswerLinks('```\nsee Docs\n```', [{ ...link, textOffset: 8 }]).text, {
      areLinksEnabled: true,
    }).html).toBe('<pre data-language=""><code>see Docs</code></pre>');
  });

  it('renders supported Agent Markdown syntax', () => {
    const result = renderMarkdown([
      'Wallet **warning:** keep `GRAM` for fees.',
      '',
      '- First item',
      '- Second *item*',
      '',
      '1. Verify the address',
      '2. Review the fee',
      '',
      '```javascript',
      'const html = "<script>safe</script>";',
      '```',
    ].join('\n'), { areLinksEnabled: false });

    expect(result.html).toContain('<strong>warning:</strong>');
    expect(result.html).toContain('<code>GRAM</code>');
    expect(result.html).toContain('<ul><li>First item</li><li>Second <em>item</em></li></ul>');
    expect(result.html).toContain('<ol><li>Verify the address</li><li>Review the fee</li></ol>');
    expect(renderMarkdown('24. Multiply first: 3 × 4 = 12.', { areLinksEnabled: false }).html)
      .toBe('<ol start="24"><li>Multiply first: 3 × 4 = 12.</li></ol>');
    expect(result.html).toContain('<pre data-language="javascript"><code>');
    expect(result.html).toContain('&lt;script&gt;safe&lt;/script&gt;');
    expect(result.html).not.toContain('<script>');
  });

  it('renders grounded HTTPS destinations in paragraphs, lists, and tables without changing the address', () => {
    const url = 'https://example.com/dapp_(swap)?asset=TON&target=USDT#trade';
    const result = renderMarkdown([
      `[**Open app**](${url})`, '', '- [Community](https://t.me/example)', '',
      '| Resource |', '| --- |', '| [Store](https://example.org/store) |',
    ].join('\n'), { areLinksEnabled: true });
    const root = document.createElement('div');
    root.innerHTML = result.html;

    expect(Array.from(root.querySelectorAll('a')).map((link) => link.getAttribute('href')))
      .toEqual([url, 'https://t.me/example', 'https://example.org/store']);
    expect(root.querySelector('a strong')?.textContent).toBe('Open app');
    expect(root.querySelector('a')?.target).toBe('_blank');
    expect(root.querySelector('a')?.rel).toBe('noopener noreferrer');
  });

  it.each([
    '[Script](javascript:alert(1))',
    '[Data](data:text/html,test)',
    '[Relative](//example.com/path)',
    '[HTTP](http://example.com)',
    '[Credentials](https://trusted.example@other.example/path)',
    '[Broken](https://)',
    '[Whitespace](https://example.com/a b)',
    String.raw`[Backslash](https://example.com\path)`,
    '[Receive](mtw://receive)',
    '[Image](file:///tmp/image)',
    '![Image](https://example.com/image.png)',
    '`[Code](https://example.com)`',
    '```text\n[Code](https://example.com)\n```',
    '```text\n[Unfinished code](https://example.com)',
    String.raw`\[Escaped](https://example.com)`,
    '[Incomplete](https://example.com',
  ])('keeps unsafe, literal, and incomplete links passive: %s', (text) => {
    const result = renderMarkdown(text, { areLinksEnabled: true });

    expect(result.html).not.toContain('<a ');
    expect(result.html).not.toContain('<img ');
  });

  it('preserves escaped destinations and literal placeholder-like text without creating extra links', () => {
    const result = renderMarkdown([
      'Literal %%AGENT_INLINE_CONTENT_0%%',
      '`%%AGENT_INLINE_CONTENT_0%%`',
      String.raw`[Docs](https://example.com/a\(b\)?filter=**active**)`,
    ].join('\n'), { areLinksEnabled: true });
    const root = document.createElement('div');
    root.innerHTML = result.html;

    expect(root.querySelectorAll('a')).toHaveLength(1);
    expect(root.querySelector('a')?.getAttribute('href')).toBe('https://example.com/a(b)?filter=**active**');
    expect(root.querySelector('code')?.textContent).toBe('%%AGENT_INLINE_CONTENT_0%%');
    expect(root.textContent).toContain('Literal %%AGENT_INLINE_CONTENT_0%%');
  });

  it('escapes link labels and attributes without allowing injected HTML', () => {
    const result = renderMarkdown(
      '[<img src=x onerror=alert(1)>](https://example.com/?q="onmouseover="alert)',
      { areLinksEnabled: true },
    );
    const root = document.createElement('div');
    root.innerHTML = result.html;

    expect(root.querySelector('img')).toBeNull();
    expect(root.querySelector('[onmouseover]')).toBeNull();
    expect(root.querySelector('a')?.textContent).toBe('<img src=x onerror=alert(1)>');
    expect(root.querySelector('a')?.getAttribute('href')).toBe('https://example.com/?q="onmouseover="alert');
  });

  it('renders blank-line-separated Agent V2 prose as semantic paragraph blocks', () => {
    const result = renderMarkdown(
      'The transfer is ready for review.\n\nConfirm the address before signing.',
      { areLinksEnabled: false },
    );

    expect(result.html).toBe(
      '<p>The transfer is ready for review.</p><p>Confirm the address before signing.</p>',
    );
  });

  it('renders escaped signs from grounded Agent V2 values without leaking backslashes', () => {
    const result = renderMarkdown(
      String.raw`Daily changes: \+1\.62% and \-2\.01%.`,
      { areLinksEnabled: false },
    );

    expect(result.html).toBe('<p>Daily changes: +1.62% and -2.01%.</p>');
  });

  it('keeps a single Agent V2 prose line break inside one paragraph', () => {
    const result = renderMarkdown(
      'The transfer is ready for review.\nConfirm the address before signing.',
      { areLinksEnabled: false },
    );

    expect(result.html).toBe(
      '<p>The transfer is ready for review. Confirm the address before signing.</p>',
    );
  });

  it('keeps unsupported and incomplete Agent V2 Markdown readable and passive', () => {
    const result = renderMarkdown([
      '# Unsupported heading',
      '> Unsupported quote',
      '<img src=x onerror=alert(1)>',
      '**unfinished',
      'Literal %%AGENT_INLINE_CODE_42%% token',
      '[Source](https://example.com/path_with_value)',
      '[Receive](mtw://receive)',
    ].join('\n'), { areLinksEnabled: false });

    expect(result.html).toContain('# Unsupported heading');
    expect(result.html).toContain('&gt; Unsupported quote');
    expect(result.html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(result.html).not.toContain('<img ');
    expect(result.html).toContain('**unfinished');
    expect(result.html).toContain('%%AGENT_INLINE_CODE_42%%');
    expect(result.html).toContain('Source (https://example.com/path_with_value)');
    expect(result.html).toContain('Receive');
    expect(result.html).not.toContain('<a ');
  });

  it('renders deterministic and grounded Agent V2 Markdown tables safely', () => {
    const markdown = [
      '| Wallet | Balance | Status |',
      '| --- | --- | --- |',
      String.raw`| Main \| **literal** \<script\> | $10 | View only |`,
    ].join('\n');
    const deterministic = renderDeterministicMarkdownTable(markdown);
    const modelAuthored = renderMarkdown(markdown, { areLinksEnabled: false });

    expect(deterministic.html).toContain('<table>');
    expect(deterministic.html).toContain('<td>Main | **literal** &lt;script&gt;</td>');
    expect(deterministic.html).not.toContain('<script>');
    expect(modelAuthored.html).toContain('<table>');
    expect(modelAuthored.html).toContain(
      '<td>Main | <strong>literal</strong> &lt;script&gt;</td>',
    );
    expect(modelAuthored.html).not.toContain('<script>');
  });

  it('keeps malformed Agent V2 table syntax as escaped prose', () => {
    const result = renderMarkdown([
      '| Wallet | Balance |',
      '| -- | --- |',
      '| <img src=x onerror=alert(1)> | 10 USD |',
    ].join('\n'), { areLinksEnabled: false });

    expect(result.html).not.toContain('<table>');
    expect(result.html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(result.html).not.toContain('<img ');
  });
});
