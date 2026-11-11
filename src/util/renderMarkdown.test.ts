import { markAnswerLinks } from './agent/answerLinkMarkers';
import renderMarkdown, { renderDeterministicMarkdownTable } from './renderMarkdown';

const WITH_LINKS = { areLinksEnabled: true, codeCopyLabel: 'Copy' };
const WITHOUT_LINKS = { areLinksEnabled: false, codeCopyLabel: 'Copy' };

describe('renderMarkdown', () => {
  it('renders answer links over their labels, as far as the revealed text goes', () => {
    const text = '- **Guide** and Docs';
    const links = [
      { textOffset: 2, textLength: 9, url: 'https://help.mywallet.io/a_(b)?x=*1*' },
      { textOffset: 16, textLength: 4, url: 'http://docs.example.com/' },
    ];

    expect(renderMarkdown(markAnswerLinks(text, links).text, WITH_LINKS).html).toBe(
      '<ul><li><a href="https://help.mywallet.io/a_(b)?x=*1*" target="_blank"'
      + ' rel="noopener noreferrer" class="agent-text-link">'
      + '<strong>Guide</strong></a> and Docs</li></ul>',
    );
    expect(renderMarkdown(markAnswerLinks('- **Gu', links).text, WITH_LINKS).html)
      .toContain('<a href="https://help.mywallet.io/a_(b)?x=*1*"');
    expect(renderMarkdown(markAnswerLinks(text, links).text, WITHOUT_LINKS).html)
      .toBe('<ul><li><strong>Guide</strong> (https://help.mywallet.io/a_(b)?x=*1*) and Docs</li></ul>');
    expect(renderMarkdown('A \uE004http%3A%2F%2Fa%2Eio\uE005B\uE006 C\uE006', WITH_LINKS).html)
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

    expect(renderMarkdown(markAnswerLinks(text, links).text, WITH_LINKS).html).toBe(
      '<p>Open <a href="mtw://settings/appearance" target="_blank"'
      + ' rel="noopener noreferrer" class="agent-text-link">Appearance</a>, '
      + 'Send, Bonus or Gram</p>',
    );
  });

  it('reads an escaped equals sign as text', () => {
    expect(renderMarkdown('\\== rates', WITH_LINKS).html).toBe('<p>== rates</p>');
  });

  it('keeps answer link labels as text inside code', () => {
    const link = { textOffset: 19, textLength: 4, url: 'https://a.io/' };

    expect(renderMarkdown(markAnswerLinks('Prices in `USD\nsee Docs and `EUR`', [link]).text, WITH_LINKS).html)
      .toBe('<p>Prices in <code class="agent-code-inline">USD see Docs and </code>EUR`</p>');
    expect(renderMarkdown(markAnswerLinks('```\nsee Docs\n```', [{ ...link, textOffset: 8 }]).text, WITH_LINKS).html)
      .toContain('<pre class="agent-code-body custom-scroll-x" data-language=""><code class="agent-code-text">see Docs'
        + '</code></pre>');
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
    ].join('\n'), WITHOUT_LINKS);

    expect(result.html).toContain('<strong>warning:</strong>');
    expect(result.html).toContain('<code class="agent-code-inline">GRAM</code>');
    expect(result.html).toContain('<ul><li>First item</li><li>Second <em>item</em></li></ul>');
    expect(result.html).toContain('<ol><li>Verify the address</li><li>Review the fee</li></ol>');
    expect(renderMarkdown('24. Multiply first: 3 × 4 = 12.', WITHOUT_LINKS).html)
      .toBe('<ol start="24"><li>Multiply first: 3 × 4 = 12.</li></ol>');
    expect(result.html).toContain('<pre class="agent-code-body custom-scroll-x" data-language="javascript">'
      + '<code class="agent-code-text">');
    expect(result.html).toContain('&lt;script&gt;safe&lt;/script&gt;');
    expect(result.html).not.toContain('<script>');
  });

  it('renders a line opened by one to six hashes and a space as a heading of its level', () => {
    expect(renderMarkdown([
      '## Market **summary**',
      'Prices rose.',
      '',
      '# One',
      '  ###### Six  ',
      '- Item',
    ].join('\n'), WITHOUT_LINKS).html).toBe(
      '<h2 class="agent-text-heading agent-text-heading-2">Market <strong>summary</strong></h2><p>Prices rose.</p>'
      + '<h1 class="agent-text-heading agent-text-heading-1">One</h1>'
      + '<h6 class="agent-text-heading agent-text-heading-6">Six</h6><ul><li>Item</li></ul>',
    );
    expect(renderMarkdown('Intro\n### Fees\nLow', WITHOUT_LINKS).html)
      .toBe('<p>Intro</p><h3 class="agent-text-heading agent-text-heading-3">Fees</h3><p>Low</p>');
    expect(renderMarkdown('## <img src=x onerror=alert(1)>', WITHOUT_LINKS).html)
      .toBe('<h2 class="agent-text-heading agent-text-heading-2">&lt;img src=x onerror=alert(1)&gt;</h2>');
    expect(renderMarkdown('#### *Fees* in `TON` on [Tonscan](https://tonscan.org/)', WITH_LINKS).html)
      .toBe('<h4 class="agent-text-heading agent-text-heading-4"><em>Fees</em> in '
        + '<code class="agent-code-inline">TON</code> on '
        + '<a href="https://tonscan.org/" target="_blank" rel="noopener noreferrer" class="agent-text-link">'
        + 'Tonscan</a></h4>');
  });

  it.each([
    ['####### Seven', '<p>####### Seven</p>'],
    ['#hashtag', '<p>#hashtag</p>'],
    ['##', '<p>##</p>'],
    ['Rank ## 2', '<p>Rank ## 2</p>'],
    [String.raw`\## Escaped`, '<p>## Escaped</p>'],
    [
      '```\n## Code\n```',
      '<pre class="agent-code-body custom-scroll-x" data-language=""><code class="agent-code-text">## Code'
      + '</code></pre>',
    ],
    [
      '```markdown\n# Unfinished code',
      '<pre class="agent-code-body custom-scroll-x" data-language="markdown"><code class="agent-code-text">'
      + '# Unfinished code</code></pre>',
    ],
  ])('keeps hashes that do not open a heading as text: %s', (text, html) => {
    const result = renderMarkdown(text, WITHOUT_LINKS).html;

    expect(result).toContain(html);
    expect(result).not.toContain('<h');
  });

  it('draws a code block with a strip that names its language, or copies it when it has none', () => {
    const root = document.createElement('div');
    root.innerHTML = renderMarkdown('```js\nconst a = "<b>";\n```\n\n```\nplain\n```', WITH_LINKS).html;
    const [named, unnamed] = Array.from(root.querySelectorAll('.agent-code-block'));

    expect(named.querySelector('button[data-agent-code-copy]')?.textContent).toBe('js');
    expect(named.querySelector('button[data-agent-code-copy]')?.getAttribute('aria-label')).toBe('Copy');
    expect(named.querySelector('pre[data-language="js"] code')?.textContent).toBe('const a = "<b>";');
    expect(named.querySelector('b')).toBeNull();
    expect(unnamed.querySelector('button[data-agent-code-copy]')?.textContent).toBe('Copy');
    expect(unnamed.querySelector('pre code')?.textContent).toBe('plain');
  });

  it('renders grounded HTTPS destinations in paragraphs, lists, and tables without changing the address', () => {
    const url = 'https://example.com/dapp_(swap)?asset=TON&target=USDT#trade';
    const result = renderMarkdown([
      `[**Open app**](${url})`, '', '- [Community](https://t.me/example)', '',
      '| Resource |', '| --- |', '| [Store](https://example.org/store) |',
    ].join('\n'), WITH_LINKS);
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
    const result = renderMarkdown(text, WITH_LINKS);

    expect(result.html).not.toContain('<a ');
    expect(result.html).not.toContain('<img ');
  });

  it('preserves escaped destinations and literal placeholder-like text without creating extra links', () => {
    const result = renderMarkdown([
      'Literal %%AGENT_INLINE_CONTENT_0%%',
      '`%%AGENT_INLINE_CONTENT_0%%`',
      String.raw`[Docs](https://example.com/a\(b\)?filter=**active**)`,
    ].join('\n'), WITH_LINKS);
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
      WITH_LINKS,
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
      WITHOUT_LINKS,
    );

    expect(result.html).toBe(
      '<p>The transfer is ready for review.</p><p>Confirm the address before signing.</p>',
    );
  });

  it('renders escaped signs from grounded Agent V2 values without leaking backslashes', () => {
    const result = renderMarkdown(
      String.raw`Daily changes: \+1\.62% and \-2\.01%.`,
      WITHOUT_LINKS,
    );

    expect(result.html).toBe('<p>Daily changes: +1.62% and -2.01%.</p>');
  });

  it('keeps a single Agent V2 prose line break as a break inside one paragraph', () => {
    const result = renderMarkdown(
      'The transfer is ready for review.\nConfirm the address before signing.',
      WITHOUT_LINKS,
    );

    expect(result.html).toBe(
      '<p>The transfer is ready for review.<br>Confirm the address before signing.</p>',
    );
  });

  it('keeps unsupported and incomplete Agent V2 Markdown readable and passive', () => {
    const result = renderMarkdown([
      '####### Unsupported heading',
      '> Unsupported quote',
      '<img src=x onerror=alert(1)>',
      '**unfinished',
      'Literal %%AGENT_INLINE_CODE_42%% token',
      '[Source](https://example.com/path_with_value)',
      '[Receive](mtw://receive)',
    ].join('\n'), WITHOUT_LINKS);

    expect(result.html).toContain('####### Unsupported heading');
    expect(result.html).not.toContain('<h');
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
    const modelAuthored = renderMarkdown(markdown, WITHOUT_LINKS);

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
    ].join('\n'), WITHOUT_LINKS);

    expect(result.html).not.toContain('<table>');
    expect(result.html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(result.html).not.toContain('<img ');
  });
});
