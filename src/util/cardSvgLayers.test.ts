import { splitCardSvg } from './cardSvgLayers';

const SVG_ROOT = '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="232" fill="none" viewBox="0 0 400 232">';

const STANDARD_CARD = `${SVG_ROOT}
<path fill="url(#a)" d="M0 0h400v232H0z"/>
<g stroke="url(#b)" stroke-width=".5"><path d="M1 1h2v2"/></g>
<g filter="url(#c)"><path fill="#f1f7ff" d="M10 10h50v50z"/></g>
<g filter="url(#d)"><path fill="url(#f)" d="M100 100h50v50z"/></g>
<path fill="url(#g)" fill-opacity=".503" d="M400 0H0v232h400z" style="mix-blend-mode:overlay"/>
<path fill="url(#g)" fill-opacity=".16" d="M400 0H0v232h400z"/>
<defs>
<filter id="c"><feGaussianBlur stdDeviation="40"/></filter>
<filter id="d"><feGaussianBlur stdDeviation="40"/></filter>
<radialGradient id="a"><stop stop-color="#123456"/></radialGradient>
<radialGradient id="g"><stop stop-color="#fff"/><stop offset="1" stop-opacity="0"/></radialGradient>
</defs>
</svg>`;

const PREMIUM_CARD = `${SVG_ROOT}
<path fill="#000" d="M0 0h400v232H0z"/>
<g filter="url(#a)"><ellipse cx="30" cy="356" fill="#484d68" rx="279" ry="136"/></g>
<defs><filter id="a"><feGaussianBlur stdDeviation="129.5"/></filter></defs>
</svg>`;

it('separates spots and contrast gradients from the base of a standard card', () => {
  const layers = splitCardSvg(STANDARD_CARD)!;

  expect(layers.spots).toHaveLength(2);
  expect(layers.spots[0]).toContain('viewBox="-128 -128 656 488"');
  expect(layers.spots[0]).toContain('M10 10h50v50z');
  expect(layers.spots[0]).not.toContain('M100 100h50v50z');
  expect(layers.spots[0]).toContain('<filter id="c">');

  expect(layers.base).toContain('width="800"');
  expect(layers.base).toContain('M0 0h400v232H0z');
  expect(layers.base).toContain('M1 1h2v2');
  expect(layers.base).not.toContain('filter="url(#c)"');
  expect(layers.base).not.toContain('M400 0H0v232h400z');

  expect(layers.contrastColor).toBe(1);
  expect(layers.contrastOpacity).toBeCloseTo(0.503);
});

it('keeps spots beyond the shader limit in the base', () => {
  const extraSpots = Array.from({ length: 3 }, (_, index) => (
    `<g filter="url(#c)"><path fill="#abcdef" d="M${index} 0h1v1z"/></g>`
  )).join('');
  const contrastStart = '<path fill="url(#g)" fill-opacity=".503"';
  const layers = splitCardSvg(STANDARD_CARD.replace(contrastStart, `${extraSpots}${contrastStart}`))!;

  expect(layers.spots).toHaveLength(3);
  expect(layers.base).not.toContain('d="M0 0h1v1z"');
  expect(layers.base).toContain('d="M1 0h1v1z"');
  expect(layers.base).toContain('d="M2 0h1v1z"');
});

it('reports a black contrast gradient without an overlay part when the overlay path has no fill', () => {
  const card = STANDARD_CARD
    .replace('<path fill="url(#g)" fill-opacity=".503"', '<path')
    .replace('<stop stop-color="#fff"/>', '<stop/>');
  const layers = splitCardSvg(card)!;

  expect(layers.contrastColor).toBe(0);
  expect(layers.contrastOpacity).toBe(0);
});

it('rasterizes a premium card as one base layer and rejects unknown artwork', () => {
  const premium = splitCardSvg(PREMIUM_CARD)!;
  expect(premium.spots).toHaveLength(0);
  expect(premium.contrastColor).toBe(-1);
  expect(premium.base).toContain('width="800"');
  expect(premium.base).toContain('<ellipse');

  expect(splitCardSvg(STANDARD_CARD.replace('viewBox="0 0 400 232"', 'viewBox="0 0 800 464"'))).toBeUndefined();
  expect(splitCardSvg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 232"/>')).toBeUndefined();
});
