import { getReturnKeyAction, insertLineBreak } from './composerReturnKey';

describe('composerReturnKey', () => {
  it('sends on Return and starts a new line with a modifier, leaving Shift to the field', () => {
    expect(getReturnKeyAction(new KeyboardEvent('keydown', { key: 'Enter' }))).toBe('send');
    expect(getReturnKeyAction(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true }))).toBe('nativeLineBreak');
    for (const modifier of ['altKey', 'metaKey', 'ctrlKey'] as const) {
      expect(getReturnKeyAction(new KeyboardEvent('keydown', { key: 'Enter', [modifier]: true }))).toBe('lineBreak');
    }
    expect(getReturnKeyAction(new KeyboardEvent('keydown', { key: 'Enter', isComposing: true }))).toBeUndefined();
    expect(getReturnKeyAction(new KeyboardEvent('keydown', { key: 'a' }))).toBeUndefined();
  });

  it('puts the line break in place of the selection and tells the field', () => {
    const input = document.createElement('textarea');
    input.value = 'First line';
    input.setSelectionRange(5, 10);
    const onInput = jest.fn();
    input.addEventListener('input', onInput);

    insertLineBreak(input);

    expect(input.value).toBe('First\n');
    expect(input.selectionStart).toBe(6);
    expect(onInput).toHaveBeenCalledTimes(1);
  });
});
