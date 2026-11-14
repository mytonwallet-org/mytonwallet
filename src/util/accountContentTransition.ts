import { ACCENT_CSS_VARIABLES } from './accentColor/constants';
import { applyStyles } from './animation';
import { animateShift } from './layoutChangeAnimation';

const DURATION_MS = 240;
const CLEANUP_GRACE_MS = 500;
const IMAGE_DECODE_TIMEOUT_MS = 120;
// Above the fixed header of the account regions and below the modals
const SNAPSHOT_Z_INDEX = 'calc(var(--z-header) + 1)';
const regions = new Set<HTMLElement>();
interface Snapshot {
  layer: HTMLElement;
  top: number;
  dispose: NoneToVoidFunction;
  start: NoneToVoidFunction;
  move: (shift: number) => void;
  isReady: boolean;
}
const snapshots = new Map<HTMLElement, Snapshot>();

export function getIsAccountContentTransitionActive() {
  return snapshots.size > 0;
}

export function registerAccountContent(node: HTMLElement) {
  regions.add(node);
  return () => {
    regions.delete(node);
    snapshots.get(node)?.dispose();
  };
}

/** Capture before the new account is rendered, while the old DOM and palette still exist */
export function captureAccountContent() {
  const origins = new Map<HTMLElement, DOMRect>();
  regions.forEach((node) => {
    const previous = snapshots.get(node);
    const previousImage = previous ? cloneWithPixels(previous.layer) : undefined;
    const previousRect = previous?.layer.getBoundingClientRect();
    if (previousImage && previous) {
      previousImage.style.opacity = getComputedStyle(previous.layer).opacity;
      previousImage.style.position = 'absolute';
      previousImage.style.transform = 'none';
      previousImage.removeAttribute('data-account-crossfade');
    }
    previous?.dispose();
    const rect = node.getBoundingClientRect();
    if (!node.isConnected || !rect.width || !rect.height || !node.getClientRects().length) return;
    // An ancestor with a transform positions its `fixed` descendants from itself, not from the viewport.
    // The probe shows where that origin is for this parent.
    const parent = node.parentElement!;
    let originRect = origins.get(parent);
    if (!originRect) {
      const origin = document.createElement('div');
      origin.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;'
        + 'margin:0;padding:0;border:0;visibility:hidden;pointer-events:none;contain:strict';
      node.after(origin);
      originRect = origin.getBoundingClientRect();
      origin.remove();
      origins.set(parent, originRect);
    }
    const scaleX = originRect.width || 1;
    const scaleY = originRect.height || 1;
    const layer = cloneWithPixels(node);
    layer.inert = true;
    layer.setAttribute('aria-hidden', 'true');
    layer.setAttribute('data-account-crossfade', '');
    const computed = getComputedStyle(node);
    // Account palettes change on ancestors. Retain the old palette in the outgoing image.
    ACCENT_CSS_VARIABLES.forEach((name) => {
      layer.style.setProperty(name, computed.getPropertyValue(name));
    });
    let background = 'transparent';
    for (let parent: HTMLElement | null = node; parent; parent = parent.parentElement) {
      const value = getComputedStyle(parent).backgroundColor;
      if (value && value !== 'transparent' && value !== 'rgba(0, 0, 0, 0)') {
        background = value;
        break;
      }
    }
    applyStyles(layer, {
      position: 'fixed', left: `${(rect.left - originRect.left) / scaleX}px`,
      top: `${(rect.top - originRect.top) / scaleY}px`,
      width: `${rect.width / scaleX}px`, height: `${rect.height / scaleY}px`, maxHeight: 'none',
      margin: '0', transform: 'none', pointerEvents: 'none',
      // `clip` does not make the layer a scroll container, which would move its `sticky` descendants.
      // Content that overflows the region sideways, such as a full-width panel, stays visible as it is live.
      overflowX: computed.overflowX === 'visible' ? 'visible' : 'clip', overflowY: 'clip',
      backgroundColor: background, zIndex: SNAPSHOT_Z_INDEX, opacity: '1', willChange: 'opacity',
    });
    const sourceElements = [node, ...node.querySelectorAll<HTMLElement>('*')];
    const copyElements = [layer, ...layer.querySelectorAll<HTMLElement>('*')];
    // Read the live tree before inserting/writing the clone. Interleaving scroll
    // reads and writes forces a layout for every descendant during edge recovery.
    const scrollPositions = sourceElements.map((source) => ({ top: source.scrollTop, left: source.scrollLeft }));
    sourceElements.forEach((source, i) => {
      const copy = copyElements[i];
      if (copy instanceof HTMLElement) {
        copy.removeAttribute('id');
        copy.style.scrollBehavior = 'auto';
      }
    });
    node.after(layer);
    scrollPositions.forEach(({ top, left }, i) => {
      if (top) copyElements[i].scrollTop = top;
      if (left) copyElements[i].scrollLeft = left;
    });
    // Preserve the visible blend, where it is on screen, when another selection interrupts this one
    if (previousImage) {
      previousImage.style.left = `${(previousRect!.left - rect.left) / scaleX}px`;
      previousImage.style.top = `${(previousRect!.top - rect.top) / scaleY}px`;
      layer.append(previousImage);
    }
    finishCloneAnimations(layer);
    let frame = 0;
    let timeout: ReturnType<typeof setTimeout>;
    let isStarted = false;
    let isMoved = false;
    const snapshot: Snapshot = { layer, top: rect.top, dispose, start, move, isReady: false };
    // The outgoing view moves with the live region, so the parts both accounts share, such as tabs, stay together
    function move(shift: number) {
      if (snapshots.get(node) !== snapshot) return;

      isMoved = true;
      layer.style.transform = `translateY(${shift / scaleY}px)`;
      animateShift(layer, 0, -shift / scaleY, DURATION_MS);
      animateShift(node, 0, -shift, DURATION_MS);
    }
    function dispose() {
      clearTimeout(timeout);
      cancelAnimationFrame(frame);
      layer.remove();
      if (snapshots.get(node) !== snapshot) return;

      snapshots.delete(node);
      startWhenAllReady();
    }
    function start() {
      if (isStarted) return;
      isStarted = true;
      // Mounting and animating a large cloned tree in one update can consume its
      // entire fade before WebKit has painted it. Keep an opaque first frame.
      frame = requestAnimationFrame(() => {
        frame = requestAnimationFrame(() => {
          if (snapshots.get(node) !== snapshot) return;
          clearTimeout(timeout);
          // A moving view stays opaque for half of its way, so the views it passes over do not show through it
          const delay = isMoved ? DURATION_MS / 2 : 0;
          const animation = layer.animate([{ opacity: 1 }, { opacity: 0 }], {
            duration: DURATION_MS, delay, easing: 'ease-in-out', fill: 'forwards',
          });
          animation.finished.then(dispose, dispose);
          timeout = setTimeout(dispose, delay + DURATION_MS + CLEANUP_GRACE_MS);
        });
      });
    }
    // Also clean up if an account update never reaches the mounted region
    timeout = setTimeout(dispose, DURATION_MS + CLEANUP_GRACE_MS);
    snapshots.set(node, snapshot);
  });
}

/** Measures where the region is for the new account and returns the mutation that moves the outgoing view with it.
 * Both run before that frame is painted, or its first frame shows the new layout around the outgoing view. */
export function alignAccountContent(node: HTMLElement) {
  const snapshot = snapshots.get(node);
  if (!snapshot) return undefined;

  const rect = node.getBoundingClientRect();
  const shift = rect.top - snapshot.top;
  // An empty region has nothing to follow, and a shift beyond the screen has no path worth showing
  if (!rect.height || !shift || Math.abs(shift) >= window.innerHeight) return undefined;

  return () => snapshot.move(shift);
}

export function playAccountContentTransition(node: HTMLElement) {
  const snapshot = snapshots.get(node);
  if (!snapshot) return;
  // Decode the incoming visible token images under the opaque outgoing view.
  // Bound the wait: a failed/slow network image must never block account changes.
  const rect = node.getBoundingClientRect();
  const images = [...node.querySelectorAll<HTMLImageElement>('img[data-account-crossfade-image]')]
    .filter((img) => getIsVisibleInContainer(img.getBoundingClientRect(), rect));
  if (!images.length) {
    markReady(snapshot);
    return;
  }
  let timeout: ReturnType<typeof setTimeout>;
  const decoded = Promise.allSettled(images.map((img) => img.decode()));
  const deadline = new Promise<void>((resolve) => {
    timeout = setTimeout(resolve, IMAGE_DECODE_TIMEOUT_MS);
  });
  void Promise.race([decoded, deadline]).then(() => {
    clearTimeout(timeout);
    if (snapshots.get(node) === snapshot) markReady(snapshot);
  });
}

function markReady(snapshot: Snapshot) {
  snapshot.isReady = true;
  startWhenAllReady();
}

// The live layout of the new account shifts, so a region that fades early shows it next to a still opaque region
function startWhenAllReady() {
  const pending = [...snapshots.values()];

  if (pending.every(({ isReady }) => isReady)) pending.forEach(({ start }) => start());
}

/** SVG image clones can repaint late in WebKit. Freeze already decoded thumbnails
 * into the outgoing layer, including when a second switch interrupts its fade. */
function cloneWithPixels(node: HTMLElement) {
  const layer = node.cloneNode(true) as HTMLElement;
  const nodeRect = node.getBoundingClientRect();
  const originals = node.querySelectorAll<HTMLCanvasElement | HTMLImageElement>(
    'canvas, img[data-account-crossfade-image]',
  );
  const copies = layer.querySelectorAll<HTMLCanvasElement | HTMLImageElement>(
    'canvas, img[data-account-crossfade-image]',
  );
  originals.forEach((source, i) => {
    const copy = copies[i];
    if (source instanceof HTMLCanvasElement && copy instanceof HTMLCanvasElement) {
      // `drawImage` throws on a canvas without pixels
      if (source.width && source.height) copy.getContext('2d')?.drawImage(source, 0, 0);
    } else if (source instanceof HTMLImageElement && source.complete && source.naturalWidth) {
      const width = source.clientWidth;
      const height = source.clientHeight;
      if (!width || !height || !getIsVisibleInContainer(source.getBoundingClientRect(), nodeRect)) return;
      const bitmap = document.createElement('canvas');
      bitmap.width = Math.ceil(width * window.devicePixelRatio);
      bitmap.height = Math.ceil(height * window.devicePixelRatio);
      bitmap.className = copy.className;
      bitmap.style.cssText = copy.style.cssText;
      bitmap.setAttribute('data-account-crossfade-image', '');
      bitmap.setAttribute('aria-hidden', 'true');
      const context = bitmap.getContext('2d');
      if (!context) return;
      const fit = getComputedStyle(source).objectFit;
      const scale = (fit === 'contain' ? Math.min : Math.max)(
        bitmap.width / source.naturalWidth, bitmap.height / source.naturalHeight,
      );
      const imageWidth = fit === 'cover' || fit === 'contain' ? source.naturalWidth * scale : bitmap.width;
      const imageHeight = fit === 'cover' || fit === 'contain' ? source.naturalHeight * scale : bitmap.height;
      context.drawImage(source, (bitmap.width - imageWidth) / 2, (bitmap.height - imageHeight) / 2,
        imageWidth, imageHeight);
      copy.replaceWith(bitmap);
    }
  });
  return layer;
}

// A clone starts its CSS animations over, and an entrance fade would replay inside the outgoing view
function finishCloneAnimations(layer: HTMLElement) {
  layer.getAnimations({ subtree: true }).forEach((animation) => {
    if (animation.effect?.getComputedTiming().endTime !== Infinity) animation.finish();
  });
}

function getIsVisibleInContainer(bounds: DOMRect, container: DOMRect) {
  return Boolean(
    bounds.width && bounds.height
    && bounds.bottom > Math.max(0, container.top) && bounds.top < Math.min(window.innerHeight, container.bottom)
    && bounds.right > Math.max(0, container.left) && bounds.left < Math.min(window.innerWidth, container.right),
  );
}
