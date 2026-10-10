import renderMarkdown from './renderMarkdown';

it('renders a grounded escaped source URL as a link to the original URL', () => {
  const result = renderMarkdown(String.raw`[Board](https://www\.federalreserve\.gov/releases/h15/)`,
    { areLinksEnabled: true });
  const root = document.createElement('div');
  root.innerHTML = result.html;

  expect(root.querySelectorAll('a')).toHaveLength(1);
  expect(root.querySelector('a')?.getAttribute('href')).toBe('https://www.federalreserve.gov/releases/h15/');
  expect(root.querySelector('a')?.textContent).toBe('Board');
  expect(result.html).not.toContain('\\');
});
