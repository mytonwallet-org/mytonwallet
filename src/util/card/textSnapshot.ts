interface CardTextPalette {
  palette: [string, string];
}

const BASELINE_MARKER_CSS = 'display:inline-block;width:0;height:0;padding:0;margin:0;border:0;vertical-align:baseline';

// The copy outside the card loses the fonts and colors it inherits there, and `direction` in RTL. Without `height`,
// the baseline marker added inside the arrow icon moves the icon's baseline by a pixel.
const COPIED_PROPERTIES = [
  'font-family', 'font-size', 'font-weight', 'font-variant-numeric', 'letter-spacing', 'line-height',
  'color', '-webkit-text-fill-color', 'direction', 'height',
];

export function captureProductionText(target: HTMLElement, profile: CardTextPalette) {
  const clone = target.cloneNode(true) as HTMLElement;
  const originals = [target, ...target.querySelectorAll<HTMLElement>('*')];
  const copies = [clone, ...clone.querySelectorAll<HTMLElement>('*')];

  originals.forEach((node, i) => {
    const styles = getComputedStyle(node);
    copies[i].style.cssText = COPIED_PROPERTIES.map((key) => `${key}:${styles.getPropertyValue(key)};`).join('');
    copies[i].style.visibility = 'visible';
  });

  Object.assign(clone.style, {
    position: 'fixed',
    left: '-10000px',
    top: '0',
    right: 'auto',
    bottom: 'auto',
    margin: '0',
    transform: 'none',
  });

  clone.setAttribute('aria-hidden', 'true');
  document.body.append(clone);

  try {
    const rect = clone.getBoundingClientRect();
    const width = Math.max(1, rect.width);
    const height = Math.max(1, rect.height);
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(width * 2);
    canvas.height = Math.ceil(height * 2);

    // The snapshot is read with `getImageData`, and reading a canvas kept on the GPU waits for all queued GPU work
    const ctx = canvas.getContext('2d', { willReadFrequently: true })!;
    ctx.scale(2, 2);

    ctx.save();
    ctx.translate(width * 0.283, height * 0.5);
    ctx.scale(width * 0.717, height * 1.7029);

    const gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
    gradient.addColorStop(0, profile.palette[0]);
    gradient.addColorStop(1, profile.palette[1]);
    ctx.restore();

    function ink(node: HTMLElement, text: string, x: number, baseline: number, isPseudo = false) {
      const style = getComputedStyle(node, isPseudo ? '::before' : undefined);
      ctx.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
      ctx.letterSpacing = style.letterSpacing === 'normal' ? '0px' : style.letterSpacing;
      ctx.direction = style.direction === 'rtl' ? 'rtl' : 'ltr';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'alphabetic';

      let opacity = 1;
      let ancestor: HTMLElement | null = node;

      while (ancestor) {
        opacity *= Number(getComputedStyle(ancestor).opacity);

        if (ancestor === clone) break;

        ancestor = ancestor.parentElement;
      }

      if (isPseudo) opacity *= Number(style.opacity);

      ctx.globalAlpha = opacity;

      const fill = style.getPropertyValue('-webkit-text-fill-color');
      const color = fill && fill !== 'currentcolor' ? fill : style.color;
      const isTransparent = color === 'transparent' || color === 'rgba(0, 0, 0, 0)';
      const background = style.backgroundColor;
      ctx.fillStyle = isTransparent ? (isPseudo && background !== 'rgba(0, 0, 0, 0)' ? background : gradient) : color;
      ctx.fillText(text, x, baseline);
      ctx.globalAlpha = 1;
    }

    const walker = document.createTreeWalker(clone, NodeFilter.SHOW_TEXT);
    const nodes: Text[] = [];
    while (walker.nextNode()) nodes.push(walker.currentNode as Text);

    for (const text of nodes) {
      const content = text.textContent ?? '';

      // The browser drops whitespace at the edges of a flex item, as around the dot of the balance change,
      // so the text is measured and drawn from its first visible character
      const start = content.search(/\S/);
      if (start === -1) continue;

      const parent = text.parentElement!;

      // The baseline marker goes into one inline wrapper with the text. Added straight to a flex parent, as with
      // the dot of the balance change, it would become a separate flex item and miss the text's baseline.
      const line = document.createElement('mtw-text-line');
      const marker = document.createElement('span');
      marker.style.cssText = BASELINE_MARKER_CSS;
      text.replaceWith(line);
      line.append(text, marker);

      const range = document.createRange();
      range.setStart(text, start);
      range.setEnd(text, content.length);

      const position = range.getBoundingClientRect();
      const baseline = marker.getBoundingClientRect().top;
      ink(parent, content.slice(start).trimEnd(), position.left - rect.left, baseline - rect.top);
      line.replaceWith(text);
    }

    for (const icon of clone.querySelectorAll<HTMLElement>('i')) {
      const content = getComputedStyle(icon, '::before').content;
      if (!content || content === 'none' || content === 'normal') continue;

      const marker = document.createElement('span');
      marker.style.cssText = BASELINE_MARKER_CSS;
      icon.append(marker);

      const position = icon.getBoundingClientRect();
      const baseline = marker.getBoundingClientRect().top;
      ink(icon, content.slice(1, -1), position.left - rect.left, baseline - rect.top, true);
      marker.remove();
    }

    return canvas;
  } finally {
    clone.remove();
  }
}

/** Position of `target` inside `root` by layout, ignoring the press and tilt transforms */
export function localPosition(target: HTMLElement, root: HTMLElement): [number, number] {
  // Safari can skip a transformed ancestor in the `offsetParent` chain, so `root` may be missing from it.
  // Both elements are measured from the top of that chain and subtracted.
  function position(element: HTMLElement): [number, number] {
    let x = 0;
    let y = 0;
    let node: HTMLElement | null = element;

    while (node) {
      x += node.offsetLeft;
      y += node.offsetTop;

      const parent = node.offsetParent as HTMLElement | null;

      if (parent) {
        x += parent.clientLeft;
        y += parent.clientTop;
      }

      node = parent;
    }

    return [x, y];
  }

  const a = position(target);
  const b = position(root);

  return [a[0] - b[0] - root.clientLeft, a[1] - b[1] - root.clientTop];
}
