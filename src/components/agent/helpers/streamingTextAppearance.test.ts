import {
  getStreamedCharacterColors,
  getStreamedCharacterGlowKeyframes,
  STREAMED_CHARACTER_DURATION_MS,
  STREAMED_CHARACTER_SAMPLE_INTERVAL_MS,
} from './streamingTextAppearance';

describe('streamed character appearance', () => {
  it('settles a character within 0.65 s, sampled every 25 ms', () => {
    const keyframes = getStreamedCharacterGlowKeyframes('rgb(0, 0, 0)', false);

    expect(STREAMED_CHARACTER_DURATION_MS).toBe(650);
    expect(STREAMED_CHARACTER_SAMPLE_INTERVAL_MS).toBe(25);
    expect(getStreamedCharacterColors('rgb(0, 0, 0)', false)).toHaveLength(27);
    expect(keyframes).toHaveLength(27);
    expect(keyframes[0].offset).toBe(0);
    expect(keyframes.at(-1)!.offset).toBe(1);
  });

  it('brings a character in from a blue glow, nearly transparent, and sharpens it within 0.15 s', () => {
    const colors = getStreamedCharacterColors('rgb(0, 0, 0)', false)!;
    const keyframes = getStreamedCharacterGlowKeyframes('rgb(0, 0, 0)', false);

    expect(parseRgba(colors[0])[3]).toBeCloseTo(0.28, 2);
    // The glow is as strong as the character shows, its tint aside
    expect(keyframes[0].textShadow).toBe('0 0 6.00px rgba(5, 109, 205, 0.135)');
    expect(getSampleAt(keyframes, 150).textShadow).toBe('none');
    expect(keyframes.filter(({ textShadow }) => textShadow !== 'none')).toHaveLength(6);
    expect(keyframes.some((keyframe) => 'color' in keyframe || 'opacity' in keyframe)).toBe(false);
  });

  it('turns from the Agent\'s blue to its violet and then into the text\'s own colour', () => {
    const colors = getStreamedCharacterColors('rgb(0, 0, 0)', false)!;

    // Blue once sharp
    expectColor(getSampleAt(colors, 150), [5, 109, 205, 1]);
    // Violet by the middle of its turn into the text's colour, half of it over the text
    expectColor(getSampleAt(colors, 400), [72, 35, 101.5, 1]);
    expectColor(colors.at(-1), [0, 0, 0, 1]);
  });

  it('takes the deep blue and violet on light and the bright ones on dark, as on iOS', () => {
    const light = getStreamedCharacterColors('rgb(0, 0, 0)', false)!;
    const dark = getStreamedCharacterColors('rgb(255, 255, 255)', true)!;

    expectColor(getSampleAt(light, 150), [5, 109, 205, 1]);
    expectColor(getSampleAt(dark, 150), [50, 158, 255, 1]);
    expect(getStreamedCharacterGlowKeyframes('rgb(255, 255, 255)', true)[0].textShadow)
      .toContain('rgba(50, 158, 255,');
    // The violet halfway over white
    expectColor(getSampleAt(dark, 400), [222.5, 186.5, 254, 1]);
    expectColor(dark.at(-1), [255, 255, 255, 1]);
  });

  it('settles a link or code in its own colour', () => {
    expectColor(getStreamedCharacterColors('rgb(0, 136, 255)', false)!.at(-1), [0, 136, 255, 1]);
    expectColor(getStreamedCharacterColors('rgba(0, 0, 0, 0.5)', false)!.at(-1), [0, 0, 0, 0.5]);
    expect(getStreamedCharacterGlowKeyframes('rgba(0, 0, 0, 0.5)', false)[0].textShadow)
      .toBe('0 0 6.00px rgba(5, 109, 205, 0.068)');
  });

  it('settles a transparent character as a valid transparent colour', () => {
    const colors = getStreamedCharacterColors('rgba(0, 0, 0, 0)', false)!;
    expect(colors.at(-1)).toBe('rgba(0, 0, 0, 0)');
    expect(colors.filter((color) => color.includes('NaN'))).toEqual([]);
  });

  it('leaves a character whose colour cannot be read in its colour, glowing as an opaque one', () => {
    expect(getStreamedCharacterColors('', false)).toBeUndefined();
    expect(getStreamedCharacterGlowKeyframes('', false)[0])
      .toEqual({ offset: 0, textShadow: '0 0 6.00px rgba(5, 109, 205, 0.135)' });
  });
});

// The sample `time` milliseconds into the character's settling
function getSampleAt<T>(samples: T[], time: number) {
  return samples[Math.round(time / STREAMED_CHARACTER_SAMPLE_INTERVAL_MS)];
}

function parseRgba(color: Keyframe[string]) {
  return String(color).match(/[\d.]+/g)!.map(Number);
}

function expectColor(color: Keyframe[string], expected: number[]) {
  parseRgba(color).forEach((channel, index) => {
    expect(Math.abs(channel - expected[index])).toBeLessThanOrEqual(index < 3 ? 1 : 0.005);
  });
}
