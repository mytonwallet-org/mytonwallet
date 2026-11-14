import type React from '../../../lib/teact/teact';

import { getIsInputMethodKey } from '../../../util/domEvents';

type ReturnKeyEvent = React.KeyboardEvent | KeyboardEvent;

/**
 * What Return does in the Agent's fields: alone it sends; with Shift, Option (Alt), Command (Meta) or Ctrl, on any
 * platform, it starts a new line, which the field does by itself only for Shift
 */
export function getReturnKeyAction(event: ReturnKeyEvent): 'send' | 'lineBreak' | 'nativeLineBreak' | undefined {
  if (event.key !== 'Enter' || getIsInputMethodKey(event)) return undefined;
  if (event.shiftKey) return 'nativeLineBreak';

  return event.altKey || event.metaKey || event.ctrlKey ? 'lineBreak' : 'send';
}

/** A line break where the caret stands, as typing one would put it, so the field's value follows */
export function insertLineBreak(input: HTMLTextAreaElement) {
  input.setRangeText('\n', input.selectionStart, input.selectionEnd, 'end');
  input.dispatchEvent(new Event('input', { bubbles: true }));
}
