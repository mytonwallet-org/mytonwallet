import { getIsInputMethodKey } from './domEvents';

describe('getIsInputMethodKey', () => {
  it('tells the Enter that confirms an input method word, also once Safari has ended the composition', () => {
    expect(getIsInputMethodKey(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true }))).toBe(true);
    expect(getIsInputMethodKey(new KeyboardEvent('keydown', { key: 'Enter', keyCode: 229 }))).toBe(true);
    expect(getIsInputMethodKey(new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13 }))).toBe(false);
  });
});
