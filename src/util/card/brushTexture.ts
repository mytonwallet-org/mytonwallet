// Brushed metal rings of the Gram card, from iOS `CardBrushTexture.radial`
const WIDTH = 400;
const HEIGHT = 232;
const SCALE = 2;

// Ring period, then the strokes repeated within it as [start, end, opacity]; a negative opacity is a dark stroke
const PATTERNS: [number, [number, number, number][]][] = [
  [11.7, [[0, 0.7, 0.32], [0.7, 1.25, -0.18]]],
  [5.2, [[0, 0.14, 0.22], [0.95, 1.85, -0.14], [1.85, 2.7, 0.16]]],
  [8.3, [[0, 0.45, -0.18], [1.15, 1.95, 0.28], [1.95, 2.15, -0.12], [4.2, 4.38, 0.12]]],
  [6.1, [[0, 0.22, 0.42], [0.22, 0.7, -0.2], [1.45, 1.58, 0.18], [2.5, 3.45, -0.16]]],
];

let texture: HTMLCanvasElement | undefined;

export function getCardBrushTexture() {
  if (texture) return texture;

  texture = document.createElement('canvas');
  texture.width = WIDTH * SCALE;
  texture.height = HEIGHT * SCALE;

  const ctx = texture.getContext('2d')!;
  ctx.scale(SCALE, SCALE);

  // Overlay blending leaves neutral gray unchanged, so only the light and dark rings show
  ctx.fillStyle = '#808080';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  ctx.translate(WIDTH / 2, HEIGHT / 2);

  const maxRadius = Math.hypot(WIDTH, HEIGHT) / 2;

  for (const [period, strokes] of PATTERNS) {
    for (let i = 0; i * period < maxRadius; i++) {
      for (const [start, end, opacity] of strokes) {
        ctx.strokeStyle = opacity > 0 ? `rgba(255, 255, 255, ${opacity})` : `rgba(0, 0, 0, ${-opacity})`;
        ctx.lineWidth = end - start;
        ctx.beginPath();
        ctx.arc(0, 0, i * period + (start + end) / 2, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
  }

  return texture;
}
